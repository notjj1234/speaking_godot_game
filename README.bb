cd "/Users/JJ/Documents/WORK VSCODE/speaking_godot_game"
"/Users/JJ/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path . --export-release "Web" "build/web/index.html"


cd "/Users/JJ/Documents/WORK VSCODE/speaking_godot_game/build/web"
python3 -m http.server 8480 --bind 127.0.0.1
open "http://127.0.0.1:8480/index.html"


