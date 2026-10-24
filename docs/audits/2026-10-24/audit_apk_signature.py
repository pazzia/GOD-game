from pathlib import Path
import hashlib
import json
import struct
import zipfile
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, ec, dsa

ROOT = Path(__file__).resolve().parent
APK = ROOT.parent / 'god-restored/Almost-God-0.2.0-debug.apk'
EXPECTED_CERT = (ROOT/'source/almost-god/tools/signing/certificate.sha256').read_text().strip()

def take_lp(data, pos=0):
    if pos+4 > len(data):
        raise ValueError('Truncated length prefix')
    size = struct.unpack_from('<I', data, pos)[0]
    start, end = pos+4, pos+4+size
    if end > len(data):
        raise ValueError('Length exceeds enclosing structure')
    return data[start:end], end

def sequence(data):
    pos = 0
    while pos < len(data):
        record, pos = take_lp(data, pos)
        yield record

raw = APK.read_bytes()
with zipfile.ZipFile(APK) as z:
    bad = z.testzip()
    if bad:
        raise ValueError('APK CRC failure: '+bad)
    zip_entries = len(z.infolist())

eocd = raw.rfind(b'PK\x05\x06', max(0, len(raw)-65557))
if eocd < 0 or eocd+22+struct.unpack_from('<H', raw, eocd+20)[0] != len(raw):
    raise ValueError('Invalid ZIP EOCD')
central = struct.unpack_from('<I', raw, eocd+16)[0]
footer_size = struct.unpack_from('<Q', raw, central-24)[0]
if raw[central-16:central] != b'APK Sig Block 42':
    raise ValueError('Missing APK Signing Block')
block_start = central-footer_size-8
if struct.unpack_from('<Q', raw, block_start)[0] != footer_size:
    raise ValueError('APK Signing Block size mismatch')
pos = block_start+8
blocks = {}
while pos < central-24:
    size = struct.unpack_from('<Q', raw, pos)[0]
    if size < 4 or pos+8+size > central-24:
        raise ValueError('Invalid APK Signing Block entry')
    block_id = struct.unpack_from('<I', raw, pos+8)[0]
    blocks[block_id] = raw[pos+12:pos+8+size]
    pos += 8+size
if pos != central-24 or 0x7109871a not in blocks:
    raise ValueError('No valid APK v2 signing entry')

signers_data, end = take_lp(blocks[0x7109871a])
if end != len(blocks[0x7109871a]):
    raise ValueError('Unexpected bytes after APK v2 signers')
signers = list(sequence(signers_data))
if not signers:
    raise ValueError('Empty APK v2 signer list')
results = []
for signer in signers:
    signed_data, pos = take_lp(signer)
    signatures_data, pos = take_lp(signer, pos)
    public_key_bytes, pos = take_lp(signer, pos)
    if pos != len(signer):
        raise ValueError('Unexpected signer trailing bytes')
    digests_data, p = take_lp(signed_data)
    certs_data, p = take_lp(signed_data, p)
    attributes, p = take_lp(signed_data, p)
    signed_data_padding = signed_data[p:]
    if signed_data_padding and signed_data_padding != b'\x00'*len(signed_data_padding):
        raise ValueError('Unexpected nonzero signed-data trailing bytes')
    certs = list(sequence(certs_data))
    if not certs:
        raise ValueError('Empty certificate chain')
    certificate = x509.load_der_x509_certificate(certs[0])
    public_key = certificate.public_key()
    if public_key.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo) != public_key_bytes:
        raise ValueError('Signing certificate and public key differ')
    certificate_sha256 = hashlib.sha256(certs[0]).hexdigest()
    if certificate_sha256 != EXPECTED_CERT:
        raise ValueError('APK certificate differs from project debug identity')
    signatures = {}
    for record in sequence(signatures_data):
        algorithm = struct.unpack_from('<I', record)[0]
        signature, end = take_lp(record, 4)
        if end != len(record):
            raise ValueError('Invalid signature record')
        signatures[algorithm] = signature
    digests = {}
    for record in sequence(digests_data):
        algorithm = struct.unpack_from('<I', record)[0]
        digest, end = take_lp(record, 4)
        if end != len(record):
            raise ValueError('Invalid digest record')
        digests[algorithm] = digest
    if list(signatures) != list(digests):
        raise ValueError('Signature and content-digest algorithm lists differ')
    available = [a for a in [0x0103, 0x0101, 0x0104, 0x0102, 0x0201, 0x0202, 0x0301] if a in signatures]
    if not available:
        raise ValueError('Unsupported APK signature algorithms')
    algorithm = available[0]
    use_sha512 = algorithm in [0x0102, 0x0104, 0x0202]
    hash_algorithm = hashes.SHA512() if use_sha512 else hashes.SHA256()
    hash_name = 'sha512' if use_sha512 else 'sha256'
    if algorithm in [0x0103, 0x0104]:
        public_key.verify(signatures[algorithm], signed_data, padding.PKCS1v15(), hash_algorithm)
    elif algorithm in [0x0101, 0x0102]:
        public_key.verify(signatures[algorithm], signed_data, padding.PSS(mgf=padding.MGF1(hash_algorithm), salt_length=hash_algorithm.digest_size), hash_algorithm)
    elif algorithm in [0x0201, 0x0202]:
        public_key.verify(signatures[algorithm], signed_data, ec.ECDSA(hash_algorithm))
    else:
        public_key.verify(signatures[algorithm], signed_data, hash_algorithm)
    adjusted_eocd = bytearray(raw[eocd:])
    struct.pack_into('<I', adjusted_eocd, 16, block_start)
    chunks = []
    for section in [raw[:block_start], raw[central:eocd], bytes(adjusted_eocd)]:
        for offset in range(0, len(section), 1024*1024):
            chunk = section[offset:offset+1024*1024]
            chunks.append(hashlib.new(hash_name, b'\xa5'+struct.pack('<I', len(chunk))+chunk).digest())
    digest = hashlib.new(hash_name, b'\x5a'+struct.pack('<I', len(chunks))+b''.join(chunks)).digest()
    if digest != digests[algorithm]:
        raise ValueError('Signed APK content digest does not match APK bytes')
    results.append({'algorithm': hex(algorithm), 'certificate_sha256': certificate_sha256,
                    'signature_valid': True, 'signed_content_digest_valid': True,
                    'authenticated_zero_padding_bytes': len(signed_data_padding),
                    'certificate_matches_project': True})
report = {'apk': APK.name, 'size_bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
          'zip_crc_valid': True, 'zip_entries': zip_entries, 'v2_signers': results,
          'scope': 'Independent APK v2 cryptographic and signed-content verification; no device installation.'}
(ROOT/'apk-signature.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
