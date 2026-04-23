# COAL Project – Dodge the Car Game (Assembly)

This is a simple Dodge the Car game made in Assembly language.

## Requirements

Before running the game, install the **MASM SDK (MASM32)**.

---

## How to Run

1. Open Command Prompt (CMD)

2. Go to MASM folder:

```
cd /d C:\masm32\bin
```

3. Go to project folder:

```
cd /d "C:\Users\hp\Desktop\BS CS 14 a\Dodge-Car"
```

4. Compile the code:

```
ml /c /coff dodgecar.asm
```

5. Link and build:

```
link /subsystem:windows dodgecar.obj
```

---

## Run the Game

After building, run the generated `.exe` file to play the game.

---

## Notes

* Make sure MASM32 is installed correctly
* File name should match: `dodgecar.asm`

---
