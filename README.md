<div align="center">
  <h3 align="center">Loqui Quest</h3>

  <p align="center">
    A 2D RPG game with voice interaction — Punch the enemy with your voice!
  </p>
  <p align="center">
    WORK IN PROGRESS
  </p>
</div>

---

## 📖 About The Project

Loqui Quest is a 2D topdown RPG game that combines JRPG combat with language learning via speech mechanics. This is game heavily inspired by games we all know and love such as **Zelda**, **Dragon Quest** and **Final Fantasy**

I started this as a learning Godot project at first and it ended up spiraling into this rabbit hole of watching YouTube tutorials and stuff lol. 

> Assets courtesy of [Michael Games](https://michaelgames.itch.io/2d-action-adventure-rpg-assets).
> Cannot thank him enough for making these assets free to use. This personal project of mine would never have started if not for him.

Original sprites will come later once the core gameplay is finished! (Or when I actually learn how to draw lol)

**Main Features:**
- 🎙️ **Speech Challenge**: Use microphone to defeat enemies by passing several speech tests.
- 🧠 **Word Counter**: Track how many times you’ve said each word.
- 🕹️ **Mic-Only Mode**: Use your voice to move and attack — Used for those who are lazy or during level specific challenges 👀.
- 📋 **Word List Menu**: Review all spoken words/sentences in the pause menu.
- ☁️ **Google Sheets Integration**: Spoken words are logged for tracking. I use Google Sheets because its free and accessible everywhere on the internet. Sue me for being broke lol.

**Supported OS:**
- Windows* (Speech challenge DOES NOT work)
- Android (Completely functional)

**Unsupported OS:**
- iOS/Mac OS (Thank you Apple for making everything expensive)
- Web Based (Trying to work on this. Primary focus)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 🚧 Built With

* Godot
* [Google Sheets API](https://developers.google.com/sheets/api)
* Google Cloud API
* Google App Script
* AWS (Planning to scrap Google and replace with AWS soon)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## ⚙️ Getting Started

### Play in your browser (desktop)
Needs Godot **4.7** with its Web export templates installed (Editor → Manage Export Templates).

```
python3 tools/web/play_in_browser.py          # macOS / Linux
py tools\web\play_in_browser.py               # Windows (or double-click tools\web\play_in_browser.cmd)
```

On Windows it finds `Godot_v4.7*_win64_console.exe` in Downloads, Desktop, Program Files and similar
places; otherwise set `$env:GODOT` to the editor exe. Use `py`/`python`, not `python3`, which on Windows is
often the Microsoft Store stub. The options below work the same with `py`.

This exports the **Web** preset to `build/web/`, serves it at **http://localhost:8060** and opens your browser.
`localhost` counts as a secure context, so the microphone works without certificate warnings.
Press Ctrl+C to stop. Other options:

| command | does |
|---|---|
| `python3 tools/web/play_in_browser.py --no-export` | serve the last export without rebuilding |
| `python3 tools/web/play_in_browser.py --export-only` | rebuild `build/web/` only |
| `python3 tools/web/play_in_browser.py --phone` | rebuild, then serve over HTTPS on your Wi-Fi for a phone or tablet (`build/serve_https.py`) |

**Testing on a phone (iOS or Android).** `--phone` prints the URL to open plus the steps for your device:

```
  📱 On your phone   https://192.168.1.23:8443/
                     https://your-mac.local:8443/   (same Wi-Fi)
```

It writes a self-signed certificate to `build/phone-certs/` (gitignored) that names your current LAN IP and
`<mac-name>.local`, and serves it at `/cert.crt`. Tap through the warning and the game runs; install that
certificate as a trusted root if you want the warning gone and the microphone prompt to behave.
It also checks the URL answers and warns when the macOS firewall is likely blocking Python.

Godot is found via `$GODOT`, `~/Downloads/Godot.app`, `/Applications/Godot*.app` or `godot` on your PATH.
Desktop browsers hide the on-screen controls; phones and tablets show them, sized to the screen.
The Windows, macOS and Android exports are unchanged.
<!-- CONTACT -->
## Contact

Orallo John James (JJ) Dalton Alvarez 
- Email: orallojohnjames@gmail.com



<p align="right">(<a href="#readme-top">back to top</a>)</p>




<!--- Acknowledgements -->
## Acknowledgements

A little acknowledgement and thank you section to those who intentionally or unintentionally helped me in the making of this little project of mine, along with some links of stuff I got/use from them!

- [Michael Games] (https://www.youtube.com/@MichaelGamesOfficial)
	- As mentioned at the top, his [assets](https://michaelgames.itch.io/2d-action-adventure-rpg-assets) were a big help in creating this project. His YouTube videos/tutorials are very cool.
- [FinePointCGI] (https://www.youtube.com/@FinePointCGI)
	- Collabed with Abdullah Nawaz Khan to create this [plugin](https://github.com/finepointcgi/SpeechToText-Android-Godot.git) that allows Speech to Text in Godot 
- [Abdullah Nawaz Khan] (https://github.com/abdullahnawazkhan)



