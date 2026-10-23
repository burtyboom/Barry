@echo off
rem Runs the game in its own window (not embedded in the editor), so fullscreen works.
rem Add -f after the path to start fullscreen.
start "" "G:\Godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
