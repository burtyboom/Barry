class_name GameVersion
extends RefCounted
## The game's version and where the online server lives. deploy.py reads VERSION from this
## file, so bump it (and add a CHANGELOG.json entry) for every release: players on an older
## version are turned away by the server and told to download the new one.

const VERSION := "1.0.0"
const TITLE := "That Ain't Living Barry!"

## The dedicated server and its website (accounts, stats, downloads). Blank = not set up yet.
const SERVER_HOST := ""
const SERVER_PORT := 7777
const SITE_URL := ""
