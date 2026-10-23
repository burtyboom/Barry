class_name Convoy
extends Node
## Convoys: a few mates travelling together, with their own private chat tab.
## Click someone's name (chat or the People list) -> invite them; they get a Join / No
## thanks popup. Everyone keeps a table of who's in which convoy (peer -> convoy id),
## kept in sync by each player announcing their own membership. Convoy chat is sent only
## to the members. Node lives at Main/Convoy on every peer (RPC paths).

signal changed

var members := {}          ## peer id -> convoy id ("" = none)
var my_id := ""
var main: Node


func _ready() -> void:
	main = get_parent()
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if members.has(id):
			members.erase(id)
			changed.emit())
	multiplayer.peer_connected.connect(func(id: int) -> void:
		# catch the newcomer up on our own convoy
		if my_id != "" and _online():
			_rpc_member.rpc_id(id, my_id))


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func me() -> int:
	return multiplayer.get_unique_id()


## Peers in my convoy (including me).
func my_members() -> Array[int]:
	var out: Array[int] = []
	if my_id == "":
		return out
	for p in members:
		if members[p] == my_id:
			out.append(p)
	return out


func in_my_convoy(peer: int) -> bool:
	return my_id != "" and members.get(peer, "") == my_id


## Ask someone to join (starts a convoy if we're not in one).
func invite(peer: int) -> void:
	if not _online() or peer == me():
		return
	if my_id == "":
		_join("%d_%d" % [me(), Time.get_ticks_msec()])
	_invite.rpc_id(peer, my_id, main.player_name)
	_toast("Convoy invite sent to %s" % main.name_of(peer))


func accept(convoy_id: String) -> void:
	_join(convoy_id)
	_toast("You joined the convoy - say g'day in the Convoy tab")
	send_chat("* joined the convoy")


func leave() -> void:
	if my_id == "":
		return
	send_chat("* left the convoy")
	_join("")


func _join(convoy_id: String) -> void:
	my_id = convoy_id
	members[me()] = convoy_id
	if _online():
		_rpc_member.rpc(convoy_id)
	changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_member(convoy_id: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if convoy_id == "":
		members.erase(from)
	else:
		members[from] = convoy_id
	changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _invite(convoy_id: String, from_name: String) -> void:
	if main.hud and main.hud.chat:
		main.hud.chat.show_invite(from_name.left(16), convoy_id)


func send_chat(text: String) -> void:
	if my_id == "":
		return
	text = text.strip_edges().left(160)
	for p in my_members():
		if p == me():
			_chat(my_id, main.player_name, text)
		else:
			_chat.rpc_id(p, my_id, main.player_name, text)


@rpc("any_peer", "call_remote", "reliable")
func _chat(convoy_id: String, who: String, text: String) -> void:
	if convoy_id != my_id or not (main.hud and main.hud.chat):
		return
	main.hud.chat.add_line("convoy", who.left(16), text.left(160), Color(0.55, 1.0, 0.6))


func _toast(t: String) -> void:
	if main.hud:
		main.hud.show_toast(t)
