/datum/unit_test/sentry_wrangler/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	user.faction = FACTION_TERRAGOV
	var/obj/item/card/id/dogtag/id = allocate(/obj/item/card/id/dogtag)
	id.access = list(ACCESS_MARINE_ENGINEERING)
	user.equip_to_slot_if_possible(id, SLOT_WEAR_ID)
	var/obj/item/sentry_wrangler/remote = allocate(/obj/item/sentry_wrangler)
	user.put_in_active_hand(remote)
	var/obj/item/weapon/gun/sentry/mini/gun = allocate(/obj/item/weapon/gun/sentry/mini)
	gun.do_deploy(user, get_step(user, EAST))
	var/obj/machinery/deployable/mounted/sentry/sentry = gun.loc
	TEST_ASSERT(istype(sentry), "Test sentry must deploy")
	var/normal_delay = gun.fire_delay
	var/obj/item/original_magazine = gun.chamber_items[gun.current_chamber_position]
	var/original_rounds = gun.rounds
	remote.melee_attack_chain(user, sentry, "left=1", FALSE)
	TEST_ASSERT_EQUAL(sentry.wrangler, remote, "Friendly engineer can connect")
	TEST_ASSERT_EQUAL(original_magazine.loc, gun, "Connecting must not eject the magazine")
	TEST_ASSERT_EQUAL(gun.rounds, original_rounds, "Connecting must preserve ammunition")
	user.a_intent = INTENT_HARM
	remote.melee_attack_chain(user, sentry, "left=1", FALSE)
	TEST_ASSERT_EQUAL(original_magazine.loc, gun, "Repeated clicks must not eject the magazine")
	TEST_ASSERT_EQUAL(sentry.wrangler, remote, "Repeated clicks in harm intent must preserve the link")
	user.a_intent = INTENT_HELP
	TEST_ASSERT(remote.valid_control(), "Connected remote must be usable")
	TEST_ASSERT_EQUAL(gun.fire_delay, normal_delay * 0.5, "Manual control doubles fire rate")
	var/turf/aim_turf = get_step(get_step(sentry, NORTH), NORTH)
	TEST_ASSERT(remote.can_fire_at(aim_turf), "Manual aiming can rotate outside the automatic firing arc")
	var/rounds_before = gun.rounds
	remote.start_remote_fire(user, aim_turf, aim_turf, "mapwindow.map", "left=1")
	TEST_ASSERT(gun.rounds < rounds_before, "Holding primary fire must fire the deployed gun")
	TEST_ASSERT_EQUAL(sentry.dir, NORTH, "Remote aiming must rotate the sentry")
	remote.stop_remote_fire()
	var/mob/living/carbon/xenomorph/drone/prone_target = allocate(/mob/living/carbon/xenomorph/drone, aim_turf)
	prone_target.lying_angle = 90
	TEST_ASSERT(remote.can_fire_at(prone_target), "Manual aiming must accept a prone xenomorph")
	// The previous shot's cooldown must elapse before another primary-fire click.
	sleep(gun.fire_delay + 1)
	remote.start_remote_fire(user, prone_target, aim_turf, "mapwindow.map", "left=1")
	TEST_ASSERT_EQUAL(gun.target, prone_target, "Primary fire must preserve the clicked mob instead of its turf")
	remote.aim_remote_fire(user, prone_target, aim_turf, aim_turf, aim_turf, "mapwindow.map", "mapwindow.map", "left=1")
	TEST_ASSERT_EQUAL(gun.target, aim_turf, "Dragging onto the floor must update the aim")
	remote.aim_remote_fire(user, aim_turf, prone_target, aim_turf, aim_turf, "mapwindow.map", "mapwindow.map", "left=1")
	TEST_ASSERT_EQUAL(gun.target, prone_target, "Dragging onto a prone mob must preserve that mob")
	var/atom/movable/projectile/projectile = allocate(/atom/movable/projectile)
	projectile.generate_bullet(gun.get_ammo())
	projectile.accuracy = 1000
	projectile.original_target = aim_turf
	TEST_ASSERT(!prone_target.projectile_hit(projectile), "A floor-targeted bullet should pass over a prone mob")
	projectile.original_target = gun.target
	TEST_ASSERT(prone_target.projectile_hit(projectile), "A bullet aimed with the remote must be able to hit the selected prone mob")
	remote.stop_remote_fire()
	var/integrity_before = sentry.obj_integrity
	sentry.take_damage(30, BRUTE, effects = FALSE)
	TEST_ASSERT(abs(sentry.obj_integrity - (integrity_before - 10.2)) < 0.1, "Shield must absorb 66% of incoming damage")
	sentry.repair_damage(10)
	TEST_ASSERT(abs(sentry.obj_integrity - (integrity_before - 6.8)) < 0.1, "Shield must reduce repair by 66%")
	user.dropItemToGround(remote)
	TEST_ASSERT_NULL(sentry.wrangler, "Dropping the remote must release the turret")
	TEST_ASSERT_EQUAL(gun.fire_delay, normal_delay, "Original fire rate must be restored")
	TEST_ASSERT(sentry.wrangler_recovery_until > world.time, "Release must start AI recovery")
	gun.set_target(aim_turf)
	TEST_ASSERT_EQUAL(gun.Fire(), NONE, "AI recovery must block even already scheduled shots")
	user.put_in_active_hand(remote)
	remote.afterattack(sentry, user, TRUE, "")
	TEST_ASSERT_NULL(sentry.wrangler, "Reconnecting must not bypass recovery")
	sentry.wrangler_recovery_until = 0
	remote.afterattack(sentry, user, TRUE, "")
	TEST_ASSERT_EQUAL(sentry.wrangler, remote, "Can reconnect after recovery")
	sentry.emp_act(1)
	TEST_ASSERT_NULL(sentry.wrangler, "EMP must break remote control")
	TEST_ASSERT_EQUAL(gun.fire_delay, normal_delay, "EMP must restore fire rate")
	sentry.remove_emp()
	sentry.wrangler_recovery_until = 0
	remote.afterattack(sentry, user, TRUE, "")
	// Headless test mobs have no hand HUD; reproduce the state change and its signal.
	user.hand = !user.hand
	SEND_SIGNAL(user, COMSIG_CARBON_SWAPPED_HANDS)
	TEST_ASSERT_NULL(sentry.wrangler, "Switching active hands must release control immediately")
	user.hand = !user.hand
	SEND_SIGNAL(user, COMSIG_CARBON_SWAPPED_HANDS)
	sentry.wrangler_recovery_until = 0
	remote.afterattack(sentry, user, TRUE, "")
	qdel(sentry)
	TEST_ASSERT_NULL(remote.controlled_sentry, "Destroying the turret must disconnect its controller")
