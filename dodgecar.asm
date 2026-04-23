.386
.model flat, stdcall
option casemap :none

; Includes
include C:\masm32\include\windows.inc
include C:\masm32\include\kernel32.inc
include C:\masm32\include\user32.inc
include C:\masm32\include\gdi32.inc

includelib C:\masm32\lib\kernel32.lib
includelib C:\masm32\lib\user32.lib
includelib C:\masm32\lib\gdi32.lib

; --------------------------------
; Constants
; --------------------------------
MAX_ENEMIES        EQU 16
MAX_STARS          EQU 80
MAX_EXPLOSIONS     EQU 10

SCREEN_WIDTH  EQU 800
SCREEN_HEIGHT EQU 600

; Road layout - 4 lanes inside a road region
ROAD_LEFT   EQU 100
ROAD_RIGHT  EQU 700
ROAD_WIDTH  EQU 600     ; 700 - 100

; Lane centers (4 lanes, each 150px wide)
; Lane 1: 100-250  center=175
; Lane 2: 250-400  center=325
; Lane 3: 400-550  center=475
; Lane 4: 550-700  center=625
LANE1_X  EQU 112   ; left edge of car in lane 1
LANE2_X  EQU 262   ; left edge of car in lane 2
LANE3_X  EQU 412   ; left edge of car in lane 3
LANE4_X  EQU 562   ; left edge of car in lane 4
LANE_WIDTH EQU 150

; Car sizes (much larger than original spaceship)
PLAYER_WIDTH  EQU 76
PLAYER_HEIGHT EQU 120
ENEMY_WIDTH   EQU 76
ENEMY_HEIGHT  EQU 120

; Colors
COLOR_RED       EQU 000000FFh
COLOR_GREEN     EQU 0000FF00h
COLOR_BLUE      EQU 00FF0000h
COLOR_YELLOW    EQU 0000FFFFh
COLOR_ORANGE    EQU 0000A5FFh
COLOR_MAGENTA   EQU 00FF00FFh
COLOR_CYAN      EQU 00FFFF00h
COLOR_BLACK     EQU 00000000h
COLOR_WHITE     EQU 00FFFFFFh
COLOR_LIGHTGRAY EQU 00C8C8C8h
COLOR_DARKGRAY  EQU 00555555h
COLOR_DARKRED   EQU 00000088h
COLOR_ROAD      EQU 00404040h
COLOR_GRASS     EQU 00205020h
COLOR_LANEMARK  EQU 00E0E000h
COLOR_DARKGREEN EQU 00003800h
COLOR_SILVER    EQU 00C0C0C0h
COLOR_NAVY      EQU 00800000h
COLOR_CRIMSON   EQU 000020DCh
COLOR_TEAL      EQU 00808000h
COLOR_MAROON    EQU 00000080h

STATE_PLAY  EQU 0
STATE_DEAD  EQU 1
STATE_TITLE EQU 3

; --------------------------------
; Structs
; --------------------------------
Enemy STRUCT
    isActive DWORD ?
    posx     DWORD ?
    posy     DWORD ?
    lane     DWORD ?   ; which lane 0-3
    carColor DWORD ?
Enemy ENDS

Star STRUCT
    posx    DWORD ?
    posy    DWORD ?
    speed   DWORD ?
    isLine  DWORD ?   ; 1 = dashed lane line, 0 = road detail
Star ENDS

Explosion STRUCT
    isActive DWORD ?
    posx     DWORD ?
    posy     DWORD ?
    timer    DWORD ?
Explosion ENDS

; --------------------------------
.DATA
enemyArr     Enemy     MAX_ENEMIES  DUP(<>)
starArr      Star      MAX_STARS    DUP(<>)
explosionArr Explosion MAX_EXPLOSIONS DUP(<>)

ClassName db "DodgeCarClass",0
AppName   db "4-Lane Dodge Car Game",0

szGameOver   db "GAME OVER",0
szRestart    db "Press R to Play Again",0
szTitle      db "DODGE THE CARS",0
szControls1  db "Use LEFT / RIGHT ARROW keys to change lanes",0
szControls2  db "Avoid oncoming cars to survive!",0
szStartMsg   db "Press ENTER to Start",0
szScore      db "SCORE: ",0
szScoreNum   db "0000000000",0    ; score buffer (10 digits)
szBestScore  db "BEST:  ",0
szBestNum    db "0000000000",0

; Game State
gameState   DWORD STATE_TITLE
frameCount  DWORD 0

; Player state
playerLane    DWORD 1       ; 0-3
playerX       DWORD LANE2_X ; pixel X (computed from lane)
playerY       DWORD 450
laneMoving    DWORD 0       ; 1 if mid-transition
laneTargetX   DWORD LANE2_X
laneSpeed     DWORD 14
moveCooldown  DWORD 0

; Score
score         DWORD 0
bestScore     DWORD 0
carsPassed    DWORD 0

; Enemy spawning
spawnTimer    DWORD 0
spawnInterval DWORD 50      ; frames between spawns (decreases over time)
gameSpeed     DWORD 15       ; pixels per frame enemies move down

; Randomizer
randSeed DWORD 87654321h

; --------------------------------
.CODE

WinMain PROTO :DWORD,:DWORD,:DWORD,:DWORD
WndProc PROTO :DWORD,:DWORD,:DWORD,:DWORD

; --- Random ---
Random PROC USES edx
    mov eax, randSeed
    imul eax, 1664525
    add eax, 1013904223
    and eax, 7FFFFFFFh
    mov randSeed, eax
    ret
Random ENDP

RandomRange PROC USES ecx edx maxVal:DWORD
    call Random
    shr eax, 4
    xor edx, edx
    mov ecx, maxVal
    div ecx
    mov eax, edx
    ret
RandomRange ENDP

; --- DrawRect ---
DrawRect PROC hdc:DWORD, px:DWORD, py:DWORD, pw:DWORD, ph:DWORD, pColor:DWORD
    LOCAL rc:RECT
    LOCAL hBrush:DWORD
    mov eax, px
    mov rc.left, eax
    add eax, pw
    mov rc.right, eax
    mov eax, py
    mov rc.top, eax
    add eax, ph
    mov rc.bottom, eax
    invoke CreateSolidBrush, pColor
    mov hBrush, eax
    invoke FillRect, hdc, ADDR rc, hBrush
    invoke DeleteObject, hBrush
    ret
DrawRect ENDP

; --- Spawn explosion ---
SpawnExplosion PROC USES esi ecx pX:DWORD, pY:DWORD
    mov esi, OFFSET explosionArr
    mov ecx, MAX_EXPLOSIONS
fe_lp:
    cmp [esi].Explosion.isActive, 0
    je fe_found
    add esi, TYPE Explosion
    dec ecx
    jnz fe_lp
    ret
fe_found:
    mov [esi].Explosion.isActive, 1
    mov eax, pX
    mov [esi].Explosion.posx, eax
    mov eax, pY
    mov [esi].Explosion.posy, eax
    mov [esi].Explosion.timer, 30
    ret
SpawnExplosion ENDP

; --- Convert score integer to string in szScoreNum ---
ScoreToStr PROC USES eax ebx ecx edx
    ; Write 10-digit score into szScoreNum
    mov eax, score
    mov ecx, 9              ; index of last digit
    lea ebx, szScoreNum
scs_lp:
    xor edx, edx
    mov esi, 10
    div esi                  ; eax = quotient, edx = remainder
    add dl, '0'
    mov [ebx+ecx], dl
    dec ecx
    cmp ecx, -1
    jl scs_done
    cmp eax, 0
    jne scs_lp
    ; fill remaining with '0'
scs_fill:
    cmp ecx, -1
    jl scs_done
    mov byte ptr [ebx+ecx], '0'
    dec ecx
    jmp scs_fill
scs_done:
    ret
ScoreToStr ENDP

BestToStr PROC USES eax ebx ecx edx
    mov eax, bestScore
    mov ecx, 9
    lea ebx, szBestNum
bts_lp:
    xor edx, edx
    mov esi, 10
    div esi
    add dl, '0'
    mov [ebx+ecx], dl
    dec ecx
    cmp ecx, -1
    jl bts_done
    cmp eax, 0
    jne bts_lp
bts_fill:
    cmp ecx, -1
    jl bts_done
    mov byte ptr [ebx+ecx], '0'
    dec ecx
    jmp bts_fill
bts_done:
    ret
BestToStr ENDP

; --- Get pixel X for a lane ---
LaneToX PROC laneNum:DWORD
    mov eax, laneNum
    .IF eax == 0
        mov eax, LANE1_X
    .ELSEIF eax == 1
        mov eax, LANE2_X
    .ELSEIF eax == 2
        mov eax, LANE3_X
    .ELSE
        mov eax, LANE4_X
    .ENDIF
    ret
LaneToX ENDP

; --- Spawn enemy car ---
SpawnEnemy PROC USES esi ecx
    mov esi, OFFSET enemyArr
    mov ecx, MAX_ENEMIES
se_lp:
    cmp [esi].Enemy.isActive, 0
    je se_found
    add esi, TYPE Enemy
    dec ecx
    jnz se_lp
    ret
se_found:
    mov [esi].Enemy.isActive, 1
    ; random lane 0-3
    invoke RandomRange, 4
    mov [esi].Enemy.lane, eax
    ; set X from lane
    invoke LaneToX, eax
    mov [esi].Enemy.posx, eax
    ; start above screen
    mov [esi].Enemy.posy, -130
    ; random color for car
    invoke RandomRange, 6
    .IF eax == 0
        mov [esi].Enemy.carColor, COLOR_RED
    .ELSEIF eax == 1
        mov [esi].Enemy.carColor, COLOR_BLUE
    .ELSEIF eax == 2
        mov [esi].Enemy.carColor, COLOR_SILVER
    .ELSEIF eax == 3
        mov [esi].Enemy.carColor, COLOR_NAVY
    .ELSEIF eax == 4
        mov [esi].Enemy.carColor, COLOR_CRIMSON
    .ELSE
        mov [esi].Enemy.carColor, COLOR_TEAL
    .ENDIF
    ret
SpawnEnemy ENDP

; --- Init / Restart ---
RestartGame PROC USES esi ecx
    mov playerLane, 1
    mov playerX, LANE2_X
    mov laneTargetX, LANE2_X
    mov laneMoving, 0
    mov moveCooldown, 0
    mov score, 0
    mov carsPassed, 0
    mov spawnTimer, 0
    mov spawnInterval, 50
    mov gameSpeed, 15
    mov frameCount, 0
    mov gameState, STATE_PLAY

    ; clear enemies
    mov esi, OFFSET enemyArr
    mov ecx, MAX_ENEMIES
clr_e:
    mov [esi].Enemy.isActive, 0
    add esi, TYPE Enemy
    dec ecx
    jnz clr_e

    ; clear explosions
    mov esi, OFFSET explosionArr
    mov ecx, MAX_EXPLOSIONS
clr_x:
    mov [esi].Explosion.isActive, 0
    add esi, TYPE Explosion
    dec ecx
    jnz clr_x

    ; reinit lane lines (stars array is used for dashed lines)
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
    mov ebx, 0
init_st:
    push ecx
    mov [esi].Star.isLine, 1
    ; spread them along 3 lane dividers x 80/3 steps
    mov eax, ebx
    xor edx, edx
    mov ecx, 3
    div ecx             ; eax = which divider (0,1,2), edx = index within divider
    ; divider X positions: 250, 400, 550
    .IF eax == 0
        mov [esi].Star.posx, 247
    .ELSEIF eax == 1
        mov [esi].Star.posx, 397
    .ELSE
        mov [esi].Star.posx, 547
    .ENDIF
    ; spread Y
    imul edx, 23
    mov [esi].Star.posy, edx
    mov [esi].Star.speed, 0   ; will be set to gameSpeed dynamically
    pop ecx
    inc ebx
    add esi, TYPE Star
    dec ecx
    jnz init_st
    ret
RestartGame ENDP

; --- Player Input ---
UpdatePlayer PROC
    cmp moveCooldown, 0
    jg dec_cd

    ; Left arrow - move left one lane
    invoke GetAsyncKeyState, VK_LEFT
    test eax, 8000h
    jz chk_right_p
    mov eax, playerLane
    cmp eax, 0
    jle chk_right_p
    dec playerLane
    invoke LaneToX, playerLane
    mov laneTargetX, eax
    mov laneMoving, 1
    mov moveCooldown, 12
    jmp chk_right_p

chk_right_p:
    invoke GetAsyncKeyState, VK_RIGHT
    test eax, 8000h
    jz up_done
    mov eax, playerLane
    cmp eax, 3
    jge up_done
    inc playerLane
    invoke LaneToX, playerLane
    mov laneTargetX, eax
    mov laneMoving, 1
    mov moveCooldown, 12
    jmp up_done

dec_cd:
    dec moveCooldown

up_done:
    ; Smooth slide toward target lane
    .IF laneMoving == 1
        mov eax, playerX
        mov ebx, laneTargetX
        .IF eax < ebx
            add eax, laneSpeed
            .IF eax >= ebx
                mov eax, ebx
                mov laneMoving, 0
            .ENDIF
            mov playerX, eax
        .ELSEIF eax > ebx
            sub eax, laneSpeed
            .IF eax <= ebx
                mov eax, ebx
                mov laneMoving, 0
            .ENDIF
            mov playerX, eax
        .ELSE
            mov laneMoving, 0
        .ENDIF
    .ENDIF
    ret
UpdatePlayer ENDP

; --- Update enemies ---
UpdateEnemies PROC USES esi ecx
    ; Spawn logic
    inc spawnTimer
    mov eax, spawnTimer
    cmp eax, spawnInterval
    jl ue_move
    mov spawnTimer, 0
    call SpawnEnemy

ue_move:
    mov esi, OFFSET enemyArr
    mov ecx, MAX_ENEMIES
ue_lp:
    cmp [esi].Enemy.isActive, 0
    je ue_nx
    ; Move down
    mov eax, gameSpeed
    add [esi].Enemy.posy, eax
    ; Passed screen bottom? -> score!
    mov eax, [esi].Enemy.posy
    cmp eax, SCREEN_HEIGHT
    jl ue_nx
    ; Car passed - increment score
    mov [esi].Enemy.isActive, 0
    inc carsPassed
    add score, 1
    ; every 10 cars passed, speed up
    mov eax, carsPassed
    xor edx, edx
    mov ecx, 10
    div ecx
    cmp edx, 0
    jne ue_nx
    ; increase speed every 10 cars
    mov eax, gameSpeed
    cmp eax, 18
    jge ue_nx
    inc gameSpeed
    ; also tighten spawn interval
    mov eax, spawnInterval
    cmp eax, 20
    jle ue_nx
    sub eax, 3
    mov spawnInterval, eax
ue_nx:
    add esi, TYPE Enemy
    dec ecx
    jnz ue_lp
    ret
UpdateEnemies ENDP

; --- Collision check (player vs enemy cars) ---
CheckCollisions PROC USES esi ecx
    cmp gameState, STATE_PLAY
    jne cc_done
    mov esi, OFFSET enemyArr
    mov ecx, MAX_ENEMIES
cc_lp:
    cmp [esi].Enemy.isActive, 0
    je cc_nx
    ; AABB: player rect vs enemy rect
    ; Horizontal overlap?
    mov eax, playerX
    add eax, PLAYER_WIDTH
    cmp eax, [esi].Enemy.posx
    jle cc_nx
    mov eax, [esi].Enemy.posx
    add eax, ENEMY_WIDTH
    cmp eax, playerX
    jle cc_nx
    ; Vertical overlap? (add a 10px forgiveness buffer)
    mov eax, playerY
    add eax, PLAYER_HEIGHT
    sub eax, 10
    cmp eax, [esi].Enemy.posy
    jle cc_nx
    mov eax, [esi].Enemy.posy
    add eax, ENEMY_HEIGHT
    sub eax, 10
    cmp eax, playerY
    jle cc_nx
    ; Collision!
    invoke SpawnExplosion, playerX, playerY
    mov gameState, STATE_DEAD
    ; Update best score
    mov eax, score
    cmp eax, bestScore
    jle cc_nx
    mov bestScore, eax
cc_nx:
    add esi, TYPE Enemy
    dec ecx
    jnz cc_lp
cc_done:
    ret
CheckCollisions ENDP
; --- Draw a car at (posX, posY) ---
DrawCar PROC hdc:DWORD, posX:DWORD, posY:DWORD, bodyCol:DWORD, isPlayer:DWORD

    ; ---- Body (main rectangle) ----
    invoke DrawRect, hdc, posX, posY, ENEMY_WIDTH, ENEMY_HEIGHT, bodyCol

    ; ---- Roof / cabin ----
    mov eax, posX
    add eax, 12
    mov ebx, eax

    mov eax, posY
    add eax, 22
    mov edx, eax

    invoke DrawRect, hdc, ebx, edx, 52, 45, COLOR_DARKGRAY

    ; ---- Windshields ----
    .IF isPlayer == 1

        ; Front windshield (top)
        mov eax, posX
        add eax, 14
        mov ebx, eax

        mov eax, posY
        add eax, 12
        mov edx, eax

        invoke DrawRect, hdc, ebx, edx, 48, 18, COLOR_CYAN

        ; Rear windshield (bottom)
        mov eax, posX
        add eax, 14
        mov ebx, eax

        mov eax, posY
        add eax, 88
        mov edx, eax

        invoke DrawRect, hdc, ebx, edx, 48, 16, COLOR_CYAN

    .ELSE

        ; Enemy front (bottom)
        mov eax, posX
        add eax, 14
        mov ebx, eax

        mov eax, posY
        add eax, 90
        mov edx, eax

        invoke DrawRect, hdc, ebx, edx, 48, 18, COLOR_CYAN

        ; Enemy rear (top)
        mov eax, posX
        add eax, 14
        mov ebx, eax

        mov eax, posY
        add eax, 12
        mov edx, eax

        invoke DrawRect, hdc, ebx, edx, 48, 16, COLOR_CYAN

    .ENDIF

    ; ---- Headlights / taillights ----
    .IF isPlayer == 1

        ; Headlights (top)
        mov eax, posX
        add eax, 6
        mov ebx, eax

        mov eax, posY
        add eax, 6
        mov edx, eax

        invoke DrawRect, hdc, ebx, edx, 18, 10, COLOR_YELLOW

        mov eax, posX
        add eax, 52
        mov ebx, eax

        invoke DrawRect, hdc, ebx, edx, 18, 10, COLOR_YELLOW

        ; Taillights (bottom)
        mov eax, posX
        add eax, 6
        mov ebx, eax

        mov eax, posY
        add eax, 104
        mov edx, eax

        invoke DrawRect, hdc, ebx, edx, 18, 10, COLOR_RED

        mov eax, posX
        add eax, 52
        mov ebx, eax

        invoke DrawRect, hdc, ebx, edx, 18, 10, COLOR_RED

    .ELSE

        ; Enemy headlights (bottom)
        mov eax, posX
        add eax, 6
        mov ebx, eax

        mov eax, posY
        add eax, 104
        mov edx, eax

        invoke DrawRect, hdc, ebx, edx, 18, 10, COLOR_YELLOW

        mov eax, posX
        add eax, 52
        mov ebx, eax

        invoke DrawRect, hdc, ebx, edx, 18, 10, COLOR_YELLOW

    .ENDIF

    ; ---- Wheels ----

    ; Top-left
    mov eax, posX
    sub eax, 8
    mov ebx, eax

    mov eax, posY
    add eax, 10
    mov edx, eax

    invoke DrawRect, hdc, ebx, edx, 10, 24, COLOR_BLACK

    ; Top-right
    mov eax, posX
    add eax, ENEMY_WIDTH
    sub eax, 2
    mov ebx, eax

    invoke DrawRect, hdc, ebx, edx, 10, 24, COLOR_BLACK

    ; Bottom-left
    mov eax, posX
    sub eax, 8
    mov ebx, eax

    mov eax, posY
    add eax, ENEMY_HEIGHT
    sub eax, 34
    mov edx, eax

    invoke DrawRect, hdc, ebx, edx, 10, 24, COLOR_BLACK

    ; Bottom-right
    mov eax, posX
    add eax, ENEMY_WIDTH
    sub eax, 2
    mov ebx, eax

    invoke DrawRect, hdc, ebx, edx, 10, 24, COLOR_BLACK

    ; ---- Center stripe ----
    mov eax, posX
    add eax, 35
    mov ebx, eax

    mov eax, posY
    add eax, 70
    mov edx, eax

    invoke DrawRect, hdc, ebx, edx, 6, 14, COLOR_LIGHTGRAY

    ret

DrawCar ENDP

; --- Main update ---
UpdateGame PROC
    inc frameCount

    ; Update lane line scroll positions
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
ul_lp:
    mov eax, gameSpeed
    add [esi].Star.posy, eax
    cmp [esi].Star.posy, SCREEN_HEIGHT
    jl ul_nx
    sub [esi].Star.posy, SCREEN_HEIGHT
ul_nx:
    add esi, TYPE Star
    dec ecx
    jnz ul_lp

    ; Update explosions
    mov esi, OFFSET explosionArr
    mov ecx, MAX_EXPLOSIONS
ux_lp:
    cmp [esi].Explosion.isActive, 0
    je ux_nx
    dec [esi].Explosion.timer
    cmp [esi].Explosion.timer, 0
    jg ux_nx
    mov [esi].Explosion.isActive, 0
ux_nx:
    add esi, TYPE Explosion
    dec ecx
    jnz ux_lp

    ; Title screen: wait for Enter
    .IF gameState == STATE_TITLE
        invoke GetAsyncKeyState, VK_RETURN
        test eax, 8000h
        jz ug_end
        call RestartGame
        jmp ug_end
    .ENDIF

    cmp gameState, STATE_PLAY
    jne ug_end

    call UpdatePlayer
    call UpdateEnemies
    call CheckCollisions

ug_end:
    ret
UpdateGame ENDP

; --- Render ---
RenderGame PROC USES esi hdc:DWORD
    LOCAL rcT:RECT
    LOCAL animT:DWORD

    mov eax, frameCount
    shr eax, 3
    and eax, 1
    mov animT, eax

    ; Setup text rect
    mov rcT.left, 0
    mov rcT.right, SCREEN_WIDTH

    ; =====================
    ; BACKGROUND
    ; =====================
    ; Left grass
    invoke DrawRect, hdc, 0, 0, ROAD_LEFT, SCREEN_HEIGHT, COLOR_GRASS
    ; Right grass
    invoke DrawRect, hdc, ROAD_RIGHT, 0, 100, SCREEN_HEIGHT, COLOR_GRASS
    ; Road
    invoke DrawRect, hdc, ROAD_LEFT, 0, ROAD_WIDTH, SCREEN_HEIGHT, COLOR_ROAD

    ; Road shoulder lines (white solid)
    invoke DrawRect, hdc, ROAD_LEFT, 0, 4, SCREEN_HEIGHT, COLOR_WHITE
    invoke DrawRect, hdc, ROAD_RIGHT-4, 0, 4, SCREEN_HEIGHT, COLOR_WHITE

    ; Dashed lane dividers (scrolling)
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
rll_lp:
    push ecx
    mov eax, [esi].Star.posx
    mov ebx, [esi].Star.posy
    invoke DrawRect, hdc, eax, ebx, 4, 16, COLOR_LANEMARK
    pop ecx
    add esi, TYPE Star
    dec ecx
    jnz rll_lp

    ; Grass edge stripes
    invoke DrawRect, hdc, 10, 0, 8, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 82, 0, 8, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 710, 0, 8, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 782, 0, 8, SCREEN_HEIGHT, COLOR_DARKGREEN

    ; =====================
    ; GAME OBJECTS
    ; =====================
    .IF gameState != STATE_TITLE
        ; Draw enemy cars
        mov esi, OFFSET enemyArr
        mov ecx, MAX_ENEMIES
re_lp:
        cmp [esi].Enemy.isActive, 0
        je re_nx
        push ecx
        invoke DrawCar, hdc, [esi].Enemy.posx, [esi].Enemy.posy, [esi].Enemy.carColor, 0
        pop ecx
re_nx:
        add esi, TYPE Enemy
        dec ecx
        jnz re_lp

        ; Draw player car (bright green, unless dead)
        .IF gameState != STATE_DEAD
            invoke DrawCar, hdc, playerX, playerY, COLOR_GREEN, 1
        .ENDIF

        ; Draw explosions
        mov esi, OFFSET explosionArr
        mov ecx, MAX_EXPLOSIONS
rx_lp:
        cmp [esi].Explosion.isActive, 0
        je rx_nx
        push ecx
        .IF [esi].Explosion.timer > 20
            mov eax, [esi].Explosion.posx
            sub eax, 20
            mov ebx, [esi].Explosion.posy
            sub ebx, 10
            invoke DrawRect, hdc, eax, ebx, 120, 80, COLOR_YELLOW
            mov eax, [esi].Explosion.posx
            sub eax, 5
            mov ebx, [esi].Explosion.posy
            sub ebx, 5
            invoke DrawRect, hdc, eax, ebx, 90, 60, COLOR_ORANGE
        .ELSEIF [esi].Explosion.timer > 10
            invoke DrawRect, hdc, [esi].Explosion.posx, [esi].Explosion.posy, 80, 60, COLOR_ORANGE
        .ELSE
            mov eax, [esi].Explosion.posx
            add eax, 15
            mov ebx, [esi].Explosion.posy
            add ebx, 10
            invoke DrawRect, hdc, eax, ebx, 50, 40, COLOR_RED
        .ENDIF
        pop ecx
rx_nx:
        add esi, TYPE Explosion
        dec ecx
        jnz rx_lp
    .ENDIF

    ; =====================
    ; HUD
    ; =====================
    invoke SetBkMode, hdc, TRANSPARENT

    .IF gameState == STATE_PLAY || gameState == STATE_DEAD
        ; Score label + number
        invoke ScoreToStr
        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 8
        mov rcT.bottom, 32
        invoke DrawTextA, hdc, ADDR szScore, -1, ADDR rcT, DT_LEFT
        mov rcT.left, 80
        invoke DrawTextA, hdc, ADDR szScoreNum, -1, ADDR rcT, DT_LEFT
        mov rcT.left, 0

        ; Best score
        invoke BestToStr
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.top, 36
        mov rcT.bottom, 60
        invoke DrawTextA, hdc, ADDR szBestScore, -1, ADDR rcT, DT_LEFT
        mov rcT.left, 80
        invoke DrawTextA, hdc, ADDR szBestNum, -1, ADDR rcT, DT_LEFT
        mov rcT.left, 0

        ; Speed indicator on right
        invoke SetTextColor, hdc, COLOR_CYAN
    .ENDIF

    ; =====================
    ; OVERLAYS
    ; =====================
    .IF gameState == STATE_TITLE
        ; Dark overlay panel
        invoke DrawRect, hdc, 150, 160, 500, 300, COLOR_BLACK
        invoke DrawRect, hdc, 154, 164, 492, 292, COLOR_DARKGRAY

        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.left, 150
        mov rcT.right, 650
        mov rcT.top, 185
        mov rcT.bottom, 230
        invoke DrawTextA, hdc, ADDR szTitle, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 255
        mov rcT.bottom, 285
        invoke DrawTextA, hdc, ADDR szControls1, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        mov rcT.top, 295
        mov rcT.bottom, 325
        invoke DrawTextA, hdc, ADDR szControls2, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        invoke SetTextColor, hdc, COLOR_GREEN
        mov rcT.top, 380
        mov rcT.bottom, 430
        invoke DrawTextA, hdc, ADDR szStartMsg, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Draw a small preview car on title
        invoke DrawCar, hdc, 355, 480, COLOR_GREEN, 1

    .ELSEIF gameState == STATE_DEAD
        invoke DrawRect, hdc, 200, 220, 400, 180, COLOR_BLACK
        invoke DrawRect, hdc, 204, 224, 392, 172, COLOR_DARKRED

        invoke SetTextColor, hdc, COLOR_RED
        mov rcT.left, 200
        mov rcT.right, 600
        mov rcT.top, 245
        mov rcT.bottom, 290
        invoke DrawTextA, hdc, ADDR szGameOver, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 310
        mov rcT.bottom, 345
        invoke DrawTextA, hdc, ADDR szRestart, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Show final score
        invoke ScoreToStr
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.top, 360
        mov rcT.bottom, 395
        invoke DrawTextA, hdc, ADDR szScore, -1, ADDR rcT, DT_CENTER
        invoke DrawTextA, hdc, ADDR szScoreNum, -1, ADDR rcT, DT_CENTER
    .ENDIF

    ret
RenderGame ENDP

; --------------------------------
; Win32 Infrastructure
; --------------------------------
WndProc PROC hwnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL hdc:DWORD, ps:PAINTSTRUCT, mDC:DWORD, mBm:DWORD, oBm:DWORD
    .IF uMsg == WM_DESTROY
        invoke KillTimer, hwnd, 1
        invoke PostQuitMessage, 0
    .ELSEIF uMsg == WM_ERASEBKGND
        mov eax, 1
        ret
    .ELSEIF uMsg == WM_TIMER
        call UpdateGame
        invoke InvalidateRect, hwnd, NULL, FALSE
    .ELSEIF uMsg == WM_PAINT
        invoke BeginPaint, hwnd, ADDR ps
        mov hdc, eax
        invoke CreateCompatibleDC, hdc
        mov mDC, eax
        invoke CreateCompatibleBitmap, hdc, SCREEN_WIDTH, SCREEN_HEIGHT
        mov mBm, eax
        invoke SelectObject, mDC, mBm
        mov oBm, eax

        invoke DrawRect, mDC, 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, COLOR_BLACK
        invoke RenderGame, mDC

        invoke BitBlt, hdc, 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, mDC, 0, 0, SRCCOPY
        invoke SelectObject, mDC, oBm
        invoke DeleteObject, mBm
        invoke DeleteDC, mDC
        invoke EndPaint, hwnd, ADDR ps
    .ELSEIF uMsg == WM_KEYDOWN
        .IF wParam == VK_ESCAPE
            invoke DestroyWindow, hwnd
        .ELSEIF wParam == 'R'
            .IF gameState == STATE_DEAD
                call RestartGame
            .ENDIF
        .ENDIF
    .ELSE
        invoke DefWindowProc, hwnd, uMsg, wParam, lParam
        ret
    .ENDIF
    xor eax, eax
    ret
WndProc ENDP

WinMain PROC hInst:DWORD, hPrevInst:DWORD, cmdLine:DWORD, cmdShow:DWORD
    LOCAL wc:WNDCLASSEX, msg:MSG, hwnd:DWORD

    invoke GetTickCount
    mov randSeed, eax

    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, CS_HREDRAW or CS_VREDRAW
    mov wc.lpfnWndProc, OFFSET WndProc
    mov wc.cbClsExtra, 0
    mov wc.cbWndExtra, 0
    mov eax, hInst
    mov wc.hInstance, eax
    mov wc.hbrBackground, COLOR_WINDOW+1
    mov wc.lpszMenuName, NULL
    mov wc.lpszClassName, OFFSET ClassName

    invoke LoadIcon, NULL, IDI_APPLICATION
    mov wc.hIcon, eax
    mov wc.hIconSm, eax
    invoke LoadCursor, NULL, IDC_ARROW
    mov wc.hCursor, eax

    invoke RegisterClassEx, ADDR wc
    invoke CreateWindowEx, 0, ADDR ClassName, ADDR AppName,
           WS_OVERLAPPEDWINDOW, 100, 50, SCREEN_WIDTH+16, SCREEN_HEIGHT+39,
           NULL, NULL, hInst, NULL
    mov hwnd, eax

    invoke SetTimer, hwnd, 1, 16, NULL
    invoke ShowWindow, hwnd, SW_SHOWNORMAL
    invoke UpdateWindow, hwnd

    ; Init lane lines
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
    mov ebx, 0
ist_lp:
    push ecx
    mov [esi].Star.isLine, 1
    mov eax, ebx
    xor edx, edx
    mov ecx, 3
    div ecx
    .IF eax == 0
        mov [esi].Star.posx, 247
    .ELSEIF eax == 1
        mov [esi].Star.posx, 397
    .ELSE
        mov [esi].Star.posx, 547
    .ENDIF
    imul edx, 23
    mov [esi].Star.posy, edx
    mov [esi].Star.speed, 5
    pop ecx
    inc ebx
    add esi, TYPE Star
    dec ecx
    jnz ist_lp

ml: invoke GetMessage, ADDR msg, NULL, 0, 0
    cmp eax, 0
    je ex
    invoke TranslateMessage, ADDR msg
    invoke DispatchMessage, ADDR msg
    jmp ml

ex: mov eax, msg.wParam
    ret
WinMain ENDP

start:
    invoke GetModuleHandle, NULL
    invoke WinMain, eax, NULL, NULL, SW_SHOWDEFAULT
    invoke ExitProcess, eax
END start