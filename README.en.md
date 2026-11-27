<p align="center"><img src="assets/brand/scrivi_icon.png" height="96" alt="Scrivi"></p>

<h1 align="center">Scrivi</h1>

<p align="center"><b>Write notation, tablature and scores.</b><br>
For Windows and Android · Open source (GPL-3.0) · <a href="README.md">Deutsch</a></p>

---

Scrivi is a music notation app for musicians, made for the **Surface with pen** on Windows and for Android tablets. It belongs to the same family as [Volti](https://github.com/rawkhawk0663/volti) (reading music), [Suona](https://github.com/rawkhawk0663/suona) (learning to read music) and [Conti](https://github.com/rawkhawk0663/conti) (bookkeeping).

Scrivi is available in **German and English**. It needs **no account**, collects **no data** and works **offline**.

> **Scrivi is still at the beginning.** Today it opens Guitar Pro files of all versions, MusicXML and MIDI, shows them neatly as notation with tablature, plays them back, and you can write in them. Next: faster input (chord line, strumming patterns, lyrics). The whole plan is in the [plan](BAUPLAN.md) (German).

## What Scrivi can do today

- **Start page:** *New piece* from templates (guitar with tab, guitar notation only, bass, lead sheet) or custom settings, *Open …* for files from anywhere, and *Recently opened* with preview, title and folder. You can also drag files into the window; on Windows, double-clicking a `.scrivi` file opens Scrivi. Settings are behind the gear at the top right.
- **File formats:** Guitar Pro of all versions (`.gp`, `.gpx`, `.gp5`, `.gp4`, `.gp3`), MusicXML (`.musicxml`, `.xml`, compressed `.mxl`) and MIDI (`.mid`). For MIDI, Scrivi snaps the notes to sixteenths and splits them into bars. For MusicXML, every staff of an instrument becomes a track of its own; a tablature staff for the same instrument supplies strings and frets.
- **Notation with tablature:** neatly engraved on A4 pages, with the systems split the way the file intends. This includes title and artist, tempo, sections (intro, verse, chorus …), chord symbols, repeats and endings, double bars, key and time changes, ties, beams, dots, tuplets, accidentals, rhythm slashes, dynamics and hairpins, lyrics and free text.
- **Guitar techniques:** palm mute (P.M.), dead notes (x), hammer-ons and pull-offs (H/P), slides, bends with amount (½, full …), ghost notes, accents, let ring, vibrato, harmonics, tapping (T), up and down strokes, tremolo picking, fermatas and grace notes.
- **Chord diagrams:** the top of the first page shows the diagrams of all chords in the piece. They come from the file; where they are missing, Scrivi uses the usual shapes for standard tuning (open or barre).
- **Tunings and capo:** for special tunings (e.g. drop D, E♭ tuning) the string names stand in front of the tab. A capo appears as “Capo 2” above the music. 7- and 8-string guitars and bass work too.
- **Choose the view:** notation and tab, notation only or tab only. In tab only, stems and beams underneath show the rhythm. Scrivi remembers your choice.
- **Viewing:** scroll with the mouse wheel, swipes, Page Up/Down, arrow keys or a pedal. Zoom with two fingers, Ctrl + mouse wheel or the buttons at the top. If a file has several tracks, choose the track in the track lanes at the bottom or in the display at the top.
- **Playback:** in the top bar, from the cursor, with all repeats, endings and jumps (D.C., D.S., coda, fine). A coloured marker follows along and the pages turn by themselves. The space bar starts and stops; afterwards the cursor sits where the music stopped. Also: tempo (25 to 200 %, pitch stays the same), count-in, metronome, a loop over any bars and a mixer (volume, mute, solo per track). The sounds are real recordings installed with Scrivi (works without internet): classical and acoustic guitar, jazz and electric guitar (also distorted), electric bass played with fingers and with a pick, plus piano, electric piano, organ, strings, choir, brass, saxophone, flute, synth and drums, with bends, slides, vibrato, palm mute and harmonics. The sounds come from FreePats and FluidR3 (free licences, see Licences).

- **Writing:** every piece is ready to write in straight away; the cursor is always there. A piece fills the whole screen. On the left, the **tool column** with music symbols, ordered in groups (note value and guitar open; expression, bar, text and piece to expand); a hint with name and shortcut appears on hover. What is set at the cursor lights up, what isn’t possible there is dimmed. At the bottom, the **fretboard**: tap string and fret to place the note, further strings make a chord; the notes of the bar light up. Every entered note sounds briefly. With the pen you can also tap notes straight onto the staff. **Search** (magnifier or Ctrl+K) finds every tool. Tool column and fretboard can be shown or hidden at the top.
- **Tracks at the bottom** (like in a recording studio program): bar numbers and the sections as coloured bands at the top, below each track as a lane with its bars and small note strokes. Tap to jump to that track and bar, drag across the bar numbers to set a loop (right-click removes it), Ctrl + mouse wheel zooms. Mute, solo and volume per track; right-click the name to rename it, choose its sound, change tuning and capo or delete it; + adds a track.
- **Properties on the right:** what is at the cursor (note, value, string and fret, chord), the bar (time, key, tempo, section, repeat), the track (name, sound, tuning, capo, volume, pan) and the piece. Tap a value to change it.
- **Tuning and capo:** common tunings (Drop D, half step down, Open G, DADGAD …) or each string separately, capo up to fret 12. Either the notes stay the same (the frets move) or the fingering stays (the notes sound different).
- **Quick writing** (“Quick” group in the tool column): type a *chord line* such as “G | Em | C D | Am7” (bars with |, % repeats the bar) and, if you like, the accompaniment straight away; *strum patterns* for any bars: strumming (quarters, eighths, pop/folk, rock, bass and strum, offbeat, waltz, six-eight) or picking (up and down, alternating bass, arpeggio) with fitting chord shapes, also in other tunings and with a capo; *paste lyrics* as a whole text and Scrivi spreads the syllables over the notes (split syllables with -); *repeat a section*, e.g. insert the chorus again after the bridge.
- **Endless view:** under *View*, all bars stand in one long line that you scroll sideways; during playback it follows along.
- **Keyboard while writing:** type a fret number (two digits quickly for 10–24), ↑/↓ changes the string, ←/→ moves from note to note (a new bar is added at the end), A–G or H places a note (with Shift added to the chord), + / − shorter/longer, full stop for a dot, T triplet, L tie, K chord, Y lyrics, Del rest, Shift + ↑/↓ semitone, Ctrl + Z/Y, Ctrl + C/X/V.
- **Saving:** pieces are `.scrivi` files that you save wherever you like (*Save* or Ctrl+S). After that Scrivi keeps every change in that file by itself. A new piece is a draft until its first save; the draft is saved continuously too and stays under *Recently opened*, so nothing is lost. Scrivi never overwrites other formats (Guitar Pro, MusicXML, MIDI): changes to them are saved as a new `.scrivi` file.

Not yet: several instruments at once (full score), PDF export. These come in the next stages. These come in the next stages.

## What Scrivi is meant to do

- **Guitar:** linked notation and tablature, chord diagrams, rhythm notation, playing techniques (bends, slides, hammer-ons, pull-offs, palm mute …), any tuning and capo.
- **Lead sheets:** melody, chord symbols, lyrics, sections, repeats, endings, segno and coda.
- **Scores:** several instruments, parts, transposition, dynamics, articulation.
- **Playback** with a following cursor, tempo, loop, count-in and metronome.
- **Import:** Guitar Pro files, MusicXML, MIDI. **Export:** PDF, MusicXML, MIDI, straight to Volti.

## Install

As soon as the first version is ready, it will be under [Releases](https://github.com/rawkhawk0663/scrivi/releases/latest).

- **Windows 10/11:** download and run `Scrivi-Setup.exe`. If Windows says "Windows protected your PC": *More info → Run anyway*. Without installing: unzip `Scrivi-Windows.zip` and run `Scrivi.exe`.
- **Android:** download and open `Scrivi-Android.apk`.
- **Android with automatic updates:** in the [Obtainium](https://github.com/ImranR98/Obtainium) app choose "Add app" and enter `https://github.com/rawkhawk0663/scrivi`.

**Updates** on Windows right in the app: *Settings → About Scrivi → Check for updates*.

## Licence

Scrivi is free software under the [GPL-3.0](LICENSE). The music font Bravura and the fonts IBM Plex Sans and Sora are under the SIL Open Font License.
