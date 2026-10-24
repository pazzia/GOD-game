extends SceneTree
## Real rigs and two confirmed simulation ticks; no predicted gameplay positions.
const Kernel=preload("res://core/simulation_kernel.gd")
const Stage=preload("res://presentation/stage_view.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures.append(message)
func run() -> void:
 var kernel=Kernel.new()
 var raw=FileAccess.get_file_as_string("res://data/levels/L06.json").replace('"goat"','"guest_animal"')
 check(kernel.load_level(JSON.parse_string(raw),48121),"valid animal instance uses an independent entity id")
 var stage=Stage.new();stage.size=Vector2(984,656);stage.kernel=kernel;root.add_child(stage);await process_frame
 check(stage._puppets.size()==3 and stage._puppets.has("entity:guest_animal"),"Felix, Plum and the authored animal instance load distinct real rigs")
 for puppet in stage._puppets.values():check(puppet.rigged,"actor uses separated accepted parts rather than a baseline image")
 check(stage._puppets.plum.position.is_equal_approx(stage._entity_position("hero")+Vector2(220*.73,-220*.59+sin(stage.clock*3)*220*.04)),"Plum hover is relative to actual Felix height and position")
 stage.play_actor("felix","stamp");stage._puppets.felix.animator.advance(.2)
 var clock: float=stage._puppets.felix.animator.current_animation_position
 stage._sync_puppets();stage._sync_puppets()
 check(stage._puppets.felix.current_state=="stamp" and stage._puppets.felix.animator.current_animation_position==clock,"same-frame pose synchronization preserves the active one-shot clock")
 check(kernel.dispatch({"type":"AssignRoute","payload":{"actor_id":"guest_animal","route_id":"cross"}}).accepted,"animal route assigned through the actual core")
 check(kernel.dispatch({"type":"RunResolution","payload":{}}).accepted,"actual navigation begins")
 stage._sample_presentation(0);kernel.advance_ticks(1);stage._sample_presentation(0);stage._sync_puppets()
 var hash_before: String=kernel.state_hash()
 var early: Vector2=stage._entity_position("guest_animal",.25)
 var late: Vector2=stage._entity_position("guest_animal",.75)
 var final: Vector2=stage._entity_position("guest_animal",1)
 var task: Dictionary=kernel.state.routes.guest_animal
 var route: Dictionary=kernel._find(kernel.definition.navigation.routes,task.route_id)
 var start: Vector2=stage.world(kernel._find(kernel.definition.navigation.nodes,route.nodes[0]).position)
 var end: Vector2=stage.world(kernel._find(kernel.definition.navigation.nodes,route.nodes[1]).position)
 var confirmed: Vector2=start.lerp(end,float(task.progress)/float(route.get("ticks_per_edge",10)))
 check(not early.is_equal_approx(late),"two render alphas inside the same core tick produce different positions")
 check(final.is_equal_approx(confirmed),"alpha one reaches the current confirmed route position")
 check(kernel.state_hash()==hash_before,"render interpolation never mutates the semantic core hash")
 check(stage._puppets["entity:guest_animal"].current_state=="move","independent animal plays its four-leg movement while hero stays ashore")
 check(stage._route_motion("hero").moving==false,"an autonomous animal route never moves its human by association")
 kernel.advance_ticks(60);stage._sample_presentation(0)
 check(stage._entity_position("guest_animal",0).is_equal_approx(stage._entity_position("guest_animal",1)),"completed route settles exactly rather than drifting or predicting past the destination")
 var next=Kernel.new();check(next.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L01.json")),48121),"replacement preview kernel loads")
 stage.kernel=next;stage._sample_presentation(0);stage._sync_puppets()
 check(stage._puppets.size()==2 and not stage._puppets.has("entity:guest_animal") and stage._route_frames.is_empty(),"kernel/level swap retires stale animal rigs and interpolation history")
 stage.reduced_motion=true;stage._sync_puppets()
 check(stage._puppets.felix.reduced_motion and stage._puppets.plum.reduced_motion,"reduced motion reaches each actor controller")
 var next_hash: String=next.state_hash()
 stage.play_actor("plum","reveal_react");stage._sync_puppets()
 check(next.state_hash()==next_hash,"cosmetic reactions never change the new comparison kernel")
 var waiting=Kernel.new();check(waiting.load_level(JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/L11.json")),48121),"thermal waiting scenario loads")
 var replay=JSON.parse_string(FileAccess.get_file_as_string("res://tests/replays/L11_solution.json"))
 for step in replay.steps:
  if step.op=="command":
   check(waiting.dispatch(step).accepted,"thermal fixture command "+step.type)
   if step.type=="RunResolution":break
  elif step.op=="advance_ticks":waiting.advance_ticks(int(step.count))
 stage.kernel=waiting;stage._sample_presentation(0);waiting.advance_ticks(1);stage._sample_presentation(0)
 var waiting_task: Dictionary=waiting.state.routes.hero
 check(not waiting_task.waiting_for.is_empty(),"actual temporal route enters WAITING_FOR_CONDITION")
 check(stage._entity_position("hero",0).is_equal_approx(stage._entity_position("hero",1)),"waiting has no interpolated or predicted movement")
 for i in range(100):
  if waiting.state.routes.hero.waiting_for.is_empty():break
  waiting.advance_ticks(1);stage._sample_presentation(0)
 check(waiting.state.routes.hero.progress>0 and not stage._entity_position("hero",0).is_equal_approx(stage._entity_position("hero",1)),"first confirmed safe movement interpolates smoothly after waiting ends")
 stage.free();await process_frame
 var file=FileAccess.open("res://tests/reports/presentation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"physical_device_tested":false},"  "));file.close()
 print("PRESENTATION: %d checks; %d failures"%[checks,failures.size()])
 for issue in failures:printerr("FAIL: "+issue)
 quit(0 if failures.is_empty() else 1)
