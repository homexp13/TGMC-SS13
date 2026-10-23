///Handheld remote for one friendly, portable sentry. The gun still fires from its own turf.
/obj/item/sentry_wrangler
	name = "Поводырь"
	desc = "Пульт ручного управления турелью. Нажмите на союзную турель вблизи для подключения, затем удерживайте ЛКМ для стрельбы и ведите курсором для наведения. Активация в руке отключает пульт. Дальность связи — 15 тайлов. Удваивает темп огня и поглощает 66% урона; после отключения автоматика перезапускается 3 секунды."
	icon = 'icons/obj/wrangler.dmi'
	icon_state = "wrangler"
	worn_icon_state = "wrangler"
	worn_icon_list = list(
		slot_l_hand_str = 'icons/mob/inhands/equipment/wrangler_left.dmi',
		slot_r_hand_str = 'icons/mob/inhands/equipment/wrangler_right.dmi',
	)
	w_class = WEIGHT_CLASS_SMALL
	///Currently linked sentry and its operator.
	var/obj/machinery/deployable/mounted/sentry/controlled_sentry
	var/mob/living/carbon/human/controller
	///Exact additive modifiers, so release does not erase other gun modifiers.
	var/fire_delay_bonus = 0
	var/burst_delay_bonus = 0
	var/autoburst_delay_bonus = 0

///Consume the interaction before mounted.attackby() treats the remote as a reload.
/obj/item/sentry_wrangler/preattack(atom/target, mob/user, params)
	if(!istype(target, /obj/machinery/deployable/mounted/sentry))
		return ..()
	afterattack(target, user, user.Adjacent(target), params)
	return TRUE

/obj/item/sentry_wrangler/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	if(!istype(target, /obj/machinery/deployable/mounted/sentry) || !proximity_flag || !ishuman(user) || user.get_active_held_item() != src || user.incapacitated())
		return
	var/obj/machinery/deployable/mounted/sentry/sentry = target
	var/obj/item/weapon/gun/gun = sentry.get_internal_item()
	if(controlled_sentry == sentry)
		return
	if(!gun || !sentry.match_iff(user) || !sentry.allowed(user) || sentry.operator || sentry.wrangler || world.time < sentry.wrangler_recovery_until || (sentry.machine_stat & (EMPED|KNOCKED_DOWN)) || (gun.turret_flags & TURRET_IMMOBILE) || !(gun.turret_flags & TURRET_ON))
		to_chat(user, span_warning("Невозможно подключиться к этой турели. Проверьте доступ, питание и состояние турели."))
		return
	if(issynth(user) && !CONFIG_GET(flag/allow_synthetic_gun_use))
		return
	if(user.interactee)
		to_chat(user, span_warning("Сначала прекратите управление другим устройством."))
		return
	release_control()
	controlled_sentry = sentry
	controller = user
	sentry.sentry_stop_fire()
	sentry.wrangler = src
	sentry.soundloop.stop()
	fire_delay_bonus = -gun.fire_delay * 0.5
	burst_delay_bonus = -gun.burst_delay * 0.5
	autoburst_delay_bonus = -gun.autoburst_delay * 0.5
	gun.modify_fire_delay(fire_delay_bonus)
	gun.modify_burst_delay(burst_delay_bonus)
	gun.modify_auto_burst_delay(autoburst_delay_bonus)
	RegisterSignal(controller, COMSIG_MOB_MOUSEDOWN, PROC_REF(start_remote_fire))
	RegisterSignal(controller, COMSIG_MOB_MOUSEDRAG, PROC_REF(aim_remote_fire))
	RegisterSignal(controller, COMSIG_MOB_MOUSEUP, PROC_REF(stop_remote_fire))
	RegisterSignals(controller, list(COMSIG_CARBON_SWAPPED_HANDS, COMSIG_MOVABLE_MOVED, COMSIG_MOB_STAT_CHANGED), PROC_REF(check_control))
	RegisterSignal(controller, COMSIG_QDELETING, PROC_REF(on_controller_deleted))
	icon_state = "wrangler_active"
	sentry.update_icon()
	START_PROCESSING(SSfastprocess, src)
	to_chat(user, span_notice("Поводырь подключён к [sentry]. Щит активен."))

/obj/item/sentry_wrangler/attack_self(mob/user)
	release_control()

/obj/item/sentry_wrangler/unequipped(mob/user, slot)
	. = ..()
	release_control()

/obj/item/sentry_wrangler/removed_from_inventory(mob/user)
	. = ..()
	release_control()

/obj/item/sentry_wrangler/Destroy()
	release_control()
	return ..()

/obj/item/sentry_wrangler/process()
	if(!valid_control())
		release_control()

/obj/item/sentry_wrangler/proc/check_control()
	SIGNAL_HANDLER
	if(!valid_control())
		release_control()

/obj/item/sentry_wrangler/proc/on_controller_deleted()
	SIGNAL_HANDLER
	release_control()

/obj/item/sentry_wrangler/proc/valid_control()
	if(QDELETED(controlled_sentry) || QDELETED(controller))
		return FALSE
	var/obj/item/weapon/gun/gun = controlled_sentry.get_internal_item()
	return loc == controller && isturf(controller.loc) && controller.get_active_held_item() == src && !controller.incapacitated() && !controller.interactee && controller.z == controlled_sentry.z && get_dist(controller, controlled_sentry) <= 15 && controlled_sentry.match_iff(controller) && !controlled_sentry.operator && !(controlled_sentry.machine_stat & (EMPED|KNOCKED_DOWN)) && gun && (gun.deploy_flags & IS_DEPLOYED) && (gun.turret_flags & TURRET_ON)

///Every shot is checked, including shots already scheduled by the autofire subsystem.
/obj/item/sentry_wrangler/proc/can_fire_at(atom/target)
	var/turf/target_turf = get_turf(target)
	return valid_control() && !QDELETED(target) && target_turf && target_turf.z == controlled_sentry.z && target_turf != controlled_sentry.loc && get_dist(controlled_sentry, target) <= 15 && controlled_sentry.check_target_path(target)

/obj/item/sentry_wrangler/proc/start_remote_fire(datum/source, atom/object, turf/location, control, params)
	SIGNAL_HANDLER
	var/list/modifiers = params2list(params)
	if(modifiers["right"] || modifiers["middle"] || modifiers["shift"] || modifiers["ctrl"] || modifiers["alt"])
		return
	// Preserve the clicked atom, as ordinary guns do, so prone targets can be hit.
	var/atom/target = get_turf_on_clickcatcher(object, controller, params)
	if(!can_fire_at(target))
		return
	controlled_sentry.setDir(get_cardinal_dir(controlled_sentry, target))
	var/obj/item/weapon/gun/gun = controlled_sentry.get_internal_item()
	gun.start_fire(controlled_sentry, target, bypass_checks = TRUE)
	controlled_sentry.firing = TRUE
	controlled_sentry.update_minimap_icon()

/obj/item/sentry_wrangler/proc/aim_remote_fire(datum/source, atom/src_object, atom/over_object, turf/src_location, turf/over_location, src_control, over_control, params)
	SIGNAL_HANDLER
	var/atom/target = get_turf_on_clickcatcher(over_object, controller, params)
	if(!can_fire_at(target))
		stop_remote_fire()
		return
	controlled_sentry.setDir(get_cardinal_dir(controlled_sentry, target))
	var/obj/item/weapon/gun/gun = controlled_sentry.get_internal_item()
	gun.set_target(target)

/obj/item/sentry_wrangler/proc/stop_remote_fire()
	SIGNAL_HANDLER
	controlled_sentry?.sentry_stop_fire()

/obj/item/sentry_wrangler/proc/release_control()
	STOP_PROCESSING(SSfastprocess, src)
	if(controller)
		UnregisterSignal(controller, list(COMSIG_MOB_MOUSEDOWN, COMSIG_MOB_MOUSEDRAG, COMSIG_MOB_MOUSEUP, COMSIG_CARBON_SWAPPED_HANDS, COMSIG_MOVABLE_MOVED, COMSIG_MOB_STAT_CHANGED, COMSIG_QDELETING))
	controller = null
	icon_state = initial(icon_state)
	if(controlled_sentry)
		var/obj/item/weapon/gun/gun = controlled_sentry.get_internal_item()
		controlled_sentry.sentry_stop_fire()
		if(gun)
			gun.modify_fire_delay(-fire_delay_bonus)
			gun.modify_burst_delay(-burst_delay_bonus)
			gun.modify_auto_burst_delay(-autoburst_delay_bonus)
		controlled_sentry.wrangler = null
		controlled_sentry.wrangler_recovery_until = world.time + 3 SECONDS
		controlled_sentry.update_icon()
		addtimer(CALLBACK(controlled_sentry, TYPE_PROC_REF(/obj/machinery/deployable/mounted/sentry, finish_wrangler_recovery)), 3 SECONDS)
	controlled_sentry = null

/obj/machinery/deployable/mounted/sentry/repair_damage(repair_amount, mob/user)
	if(wrangler || world.time < wrangler_recovery_until)
		repair_amount *= 0.34
	return ..()

/obj/machinery/deployable/mounted/sentry/proc/finish_wrangler_recovery()
	update_icon()
	var/obj/item/weapon/gun/gun = get_internal_item()
	if(!wrangler && gun && (gun.turret_flags & TURRET_ON) && !(machine_stat & (EMPED|KNOCKED_DOWN)))
		soundloop.start()
		process()
