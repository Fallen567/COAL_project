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
COLOR_ROAD      EQU 00484848h
COLOR_GRASS     EQU 00226622h
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
AppName   db "DODGE THE CARS  |  COAL Project",0

szGameOver   db "GAME OVER",0
szRestart    db "Press R to Play Again",0
szTitle      db "DODGE THE CARS",0
szControls1  db "Use LEFT / RIGHT ARROW keys to change lanes",0
szControls2  db "Avoid oncoming cars to survive!",0
szStartMsg   db "Press ENTER to Start",0
szScore      db "SCORE: ",0
szScoreNum   db 11 dup(0)   ; 10 chars + NULL
szBestScore  db "BEST:  ",0
szBestNum    db 11 dup(0)


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
spawnInterval DWORD 60      ; frames between spawns (decreases over time)
gameSpeed     DWORD 10       ; pixels per frame enemies move down
scoreFlashTimer DWORD 0

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
ScoreToStr PROC USES eax ebx ecx edx edi

    lea edi, szScoreNum

    ; Fill buffer with spaces
    mov ecx, 10
    mov al, ' '
    rep stosb

    mov byte ptr [edi], 0   ; NULL terminate

    mov eax, score
    lea edi, szScoreNum
    add edi, 9              ; last digit position

convert_loop:
    xor edx, edx
    mov ecx, 10
    div ecx
    add dl, '0'
    mov [edi], dl
    dec edi
    cmp eax, 0
    jne convert_loop

    ret
ScoreToStr ENDP

BestToStr PROC USES eax ebx ecx edx edi

    lea edi, szBestNum

    ; Fill buffer with spaces
    mov ecx, 10
    mov al, ' '
    rep stosb

    mov byte ptr [edi], 0

    mov eax, bestScore
    lea edi, szBestNum
    add edi, 9

convert_loop:
    xor edx, edx
    mov ecx, 10
    div ecx
    add dl, '0'
    mov [edi], dl
    dec edi
    cmp eax, 0
    jne convert_loop

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

UpdateEnemies PROC USES esi ecx

    ; -------- Spawn logic --------
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

    ; -------- Move enemy --------
    mov eax, gameSpeed
    add [esi].Enemy.posy, eax

    ; -------- Check if passed screen --------
    mov eax, [esi].Enemy.posy
    cmp eax, SCREEN_HEIGHT
    jl ue_nx

    ; -------- Enemy passed → score --------
    mov [esi].Enemy.isActive, 0

    inc carsPassed
    inc score                ; cleaner than add score,1
    mov scoreFlashTimer, 6

    ; -------- Milestone every 10 cars --------
    mov eax, carsPassed
    xor edx, edx
    mov ecx, 10
    div ecx                  ; edx = remainder

    cmp edx, 0
    jne ue_nx

    ; -------- Increase difficulty --------

    ; Speed increase (max 30)
    mov eax, gameSpeed
    cmp eax, 30
    jge skip_speed
    add gameSpeed, 2
skip_speed:

    ; Spawn faster (min 12)
    mov eax, spawnInterval
    cmp eax, 12
    jle ue_nx
    sub spawnInterval, 4

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

    ; ---- Main Body ----
    invoke DrawRect, hdc, posX, posY, ENEMY_WIDTH, ENEMY_HEIGHT, bodyCol

    ; ---- Body side accent lines (darker shade on edges) ----
    invoke DrawRect, hdc, posX, posY, 4, ENEMY_HEIGHT, COLOR_DARKGRAY
    mov eax, posX
    add eax, ENEMY_WIDTH
    sub eax, 4
    invoke DrawRect, hdc, eax, posY, 4, ENEMY_HEIGHT, COLOR_DARKGRAY

    ; ---- Cabin / Roof ----
    mov eax, posX
    add eax, 10
    mov ebx, posY
    add ebx, 24
    invoke DrawRect, hdc, eax, ebx, 56, 50, COLOR_DARKGRAY

    ; ---- Cabin inner highlight (makes roof look 3D) ----
    mov eax, posX
    add eax, 14
    mov ebx, posY
    add ebx, 27
    invoke DrawRect, hdc, eax, ebx, 48, 8, 00606060h

    ; ---- Door line (horizontal divider across body) ----
    mov eax, posX
    add eax, 4
    mov ebx, posY
    add ebx, 74
    invoke DrawRect, hdc, eax, ebx, 68, 3, COLOR_DARKGRAY

    ; ---- Door handle left ----
    mov eax, posX
    add eax, 8
    mov ebx, posY
    add ebx, 79
    invoke DrawRect, hdc, eax, ebx, 14, 4, COLOR_LIGHTGRAY

    ; ---- Door handle right ----
    mov eax, posX
    add eax, 54
    mov ebx, posY
    add ebx, 79
    invoke DrawRect, hdc, eax, ebx, 14, 4, COLOR_LIGHTGRAY

    ; ---- Windshields ----
    .IF isPlayer == 1
        ; Front windshield (top of car)
        mov eax, posX
        add eax, 13
        mov ebx, posY
        add ebx, 10
        invoke DrawRect, hdc, eax, ebx, 50, 20, COLOR_CYAN

        ; Rear windshield (bottom of car)
        mov eax, posX
        add eax, 13
        mov ebx, posY
        add ebx, 88
        invoke DrawRect, hdc, eax, ebx, 50, 18, COLOR_CYAN

    .ELSE
        ; Enemy front windshield (bottom - facing player)
        mov eax, posX
        add eax, 13
        mov ebx, posY
        add ebx, 88
        invoke DrawRect, hdc, eax, ebx, 50, 18, COLOR_CYAN

        ; Enemy rear windshield (top)
        mov eax, posX
        add eax, 13
        mov ebx, posY
        add ebx, 10
        invoke DrawRect, hdc, eax, ebx, 50, 20, COLOR_CYAN
    .ENDIF

    ; ---- Headlights & Taillights ----
    .IF isPlayer == 1
        ; --- Headlights (top) LEFT ---
        mov eax, posX
        add eax, 5
        mov ebx, posY
        add ebx, 4
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_YELLOW

        ; headlight inner glow
        mov eax, posX
        add eax, 7
        mov ebx, posY
        add ebx, 5
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_WHITE

        ; --- Headlights (top) RIGHT ---
        mov eax, posX
        add eax, 49
        mov ebx, posY
        add ebx, 4
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_YELLOW

        ; headlight inner glow
        mov eax, posX
        add eax, 51
        mov ebx, posY
        add ebx, 5
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_WHITE

        ; --- Taillights (bottom) LEFT ---
        mov eax, posX
        add eax, 5
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 12
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_RED

        ; taillight inner
        mov eax, posX
        add eax, 7
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 10
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_DARKRED

        ; --- Taillights (bottom) RIGHT ---
        mov eax, posX
        add eax, 49
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 12
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_RED

        ; taillight inner
        mov eax, posX
        add eax, 51
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 10
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_DARKRED

    .ELSE
        ; --- Enemy headlights (bottom - facing player) LEFT ---
        mov eax, posX
        add eax, 5
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 12
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_YELLOW

        ; headlight inner glow
        mov eax, posX
        add eax, 7
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 10
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_WHITE

        ; --- Enemy headlights (bottom) RIGHT ---
        mov eax, posX
        add eax, 49
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 12
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_YELLOW

        ; headlight inner glow
        mov eax, posX
        add eax, 51
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 10
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_WHITE

        ; --- Enemy taillights (top) LEFT ---
        mov eax, posX
        add eax, 5
        mov ebx, posY
        add ebx, 4
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_RED

        ; taillight inner
        mov eax, posX
        add eax, 7
        mov ebx, posY
        add ebx, 5
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_DARKRED

        ; --- Enemy taillights (top) RIGHT ---
        mov eax, posX
        add eax, 49
        mov ebx, posY
        add ebx, 4
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_RED

        ; taillight inner
        mov eax, posX
        add eax, 51
        mov ebx, posY
        add ebx, 5
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_DARKRED
    .ENDIF

    ; ---- Wheels (pure black, all 4 corners) ----

    ; Top-left
    mov eax, posX
    sub eax, 8
    mov ebx, posY
    add ebx, 8
    invoke DrawRect, hdc, eax, ebx, 12, 28, COLOR_BLACK

    ; Top-right
    mov eax, posX
    add eax, ENEMY_WIDTH
    sub eax, 4
    mov ebx, posY
    add ebx, 8
    invoke DrawRect, hdc, eax, ebx, 12, 28, COLOR_BLACK

    ; Bottom-left
    mov eax, posX
    sub eax, 8
    mov ebx, posY
    add ebx, ENEMY_HEIGHT
    sub ebx, 36
    invoke DrawRect, hdc, eax, ebx, 12, 28, COLOR_BLACK

    ; Bottom-right
    mov eax, posX
    add eax, ENEMY_WIDTH
    sub eax, 4
    mov ebx, posY
    add ebx, ENEMY_HEIGHT
    sub ebx, 36
    invoke DrawRect, hdc, eax, ebx, 12, 28, COLOR_BLACK

    ; ---- Center hood stripe ----
    mov eax, posX
    add eax, 34
    mov ebx, posY
    add ebx, 2
    invoke DrawRect, hdc, eax, ebx, 8, 10, COLOR_LIGHTGRAY

    ret

DrawCar ENDP

UpdateGame PROC
    inc frameCount

    ; ===== Score flash timer (NEW) =====
    cmp scoreFlashTimer, 0
    jle no_flash_dec
    dec scoreFlashTimer
no_flash_dec:

    ; ===== Update lane line scroll =====
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

    ; ===== Update explosions =====
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

    ; ===== Title screen =====
    .IF gameState == STATE_TITLE
        invoke GetAsyncKeyState, VK_RETURN
        test eax, 8000h
        jz ug_end
        call RestartGame
        jmp ug_end
    .ENDIF

    ; ===== Gameplay =====
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

    ; Left grass base
    invoke DrawRect, hdc, 0, 0, ROAD_LEFT, SCREEN_HEIGHT, COLOR_GRASS
    ; Right grass base
    invoke DrawRect, hdc, ROAD_RIGHT, 0, 100, SCREEN_HEIGHT, COLOR_GRASS

    ; Grass texture stripes (left side)
    invoke DrawRect, hdc, 8,  0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 22, 0, 3, SCREEN_HEIGHT, 00185018h
    invoke DrawRect, hdc, 40, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 55, 0, 3, SCREEN_HEIGHT, 00185018h
    invoke DrawRect, hdc, 70, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN

    ; Grass texture stripes (right side)
    invoke DrawRect, hdc, 716, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 730, 0, 3, SCREEN_HEIGHT, 00185018h
    invoke DrawRect, hdc, 748, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 763, 0, 3, SCREEN_HEIGHT, 00185018h
    invoke DrawRect, hdc, 778, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN

    ; Road base
    invoke DrawRect, hdc, ROAD_LEFT, 0, ROAD_WIDTH, SCREEN_HEIGHT, COLOR_ROAD

    ; Road edge shadow (left inner)
    invoke DrawRect, hdc, ROAD_LEFT, 0, 8, SCREEN_HEIGHT, 00202020h
    ; Road edge shadow (right inner)
    invoke DrawRect, hdc, ROAD_RIGHT-8, 0, 8, SCREEN_HEIGHT, 00202020h

    ; Road shoulder lines (white solid)
    invoke DrawRect, hdc, ROAD_LEFT,   0, 5, SCREEN_HEIGHT, COLOR_WHITE
    invoke DrawRect, hdc, ROAD_RIGHT-5, 0, 5, SCREEN_HEIGHT, COLOR_WHITE

    ; Curb stripes left (red/white alternating - use lane mark scroll)
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
crb_lp:
    push ecx
    mov eax, [esi].Star.posy
    ; alternate red and white every 24px
    xor edx, edx
    mov ebx, 48
    div ebx
    .IF edx < 24
        invoke DrawRect, hdc, 93, [esi].Star.posy, 7, 24, COLOR_RED
    .ELSE
        invoke DrawRect, hdc, 93, [esi].Star.posy, 7, 24, COLOR_WHITE
    .ENDIF
    pop ecx
    add esi, TYPE Star
    dec ecx
    jnz crb_lp

    ; Curb stripes right
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
crb2_lp:
    push ecx
    mov eax, [esi].Star.posy
    xor edx, edx
    mov ebx, 48
    div ebx
    .IF edx < 24
        invoke DrawRect, hdc, 700, [esi].Star.posy, 7, 24, COLOR_RED
    .ELSE
        invoke DrawRect, hdc, 700, [esi].Star.posy, 7, 24, COLOR_WHITE
    .ENDIF
    pop ecx
    add esi, TYPE Star
    dec ecx
    jnz crb2_lp

    ; Dashed lane dividers (scrolling) - wider and more visible
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
rll_lp:
    push ecx
    mov eax, [esi].Star.posx
    mov ebx, [esi].Star.posy
    invoke DrawRect, hdc, eax, ebx, 5, 20, COLOR_LANEMARK
    pop ecx
    add esi, TYPE Star
    dec ecx
    jnz rll_lp

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

    ; HUD background panel
    ; Outer border
    invoke DrawRect, hdc, 0, 0, 240, 80, COLOR_YELLOW

    ; Inner panel
    invoke DrawRect, hdc, 3, 3, 234, 74, 00101010h

; Top glow strip
    invoke DrawRect, hdc, 3, 3, 234, 6, COLOR_YELLOW

    .IF gameState == STATE_PLAY || gameState == STATE_DEAD

        ; ===== SCORE LABEL =====
        invoke SetTextColor, hdc, COLOR_CYAN
        mov rcT.left, 10
        mov rcT.right, 120
        mov rcT.top, 10
        mov rcT.bottom, 35
        invoke DrawTextA, hdc, ADDR szScore, -1, ADDR rcT, DT_LEFT or DT_SINGLELINE

        ; ===== SCORE VALUE =====
        invoke ScoreToStr

        ; ---- FLASH LOGIC HERE ----
        cmp scoreFlashTimer, 0
        jle normal_color

        invoke SetTextColor, hdc, COLOR_GREEN
        jmp draw_score

        normal_color:
        invoke SetTextColor, hdc, COLOR_WHITE

        draw_score:
        mov rcT.left, 100
        mov rcT.right, 230
        invoke DrawTextA, hdc, ADDR szScoreNum, -1, ADDR rcT, DT_LEFT or DT_SINGLELINE  


        ; ===== BEST LABEL =====
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.left, 10
        mov rcT.right, 120
        mov rcT.top, 40
        mov rcT.bottom, 65
        invoke DrawTextA, hdc, ADDR szBestScore, -1, ADDR rcT, DT_LEFT or DT_SINGLELINE

        ; ===== BEST VALUE =====
        invoke BestToStr
        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.left, 100
        mov rcT.right, 230
        invoke DrawTextA, hdc, ADDR szBestNum, -1, ADDR rcT, DT_LEFT or DT_SINGLELINE

        ; Reset rect (important)
        mov rcT.left, 0
        mov rcT.right, SCREEN_WIDTH

    .ENDIF

    ; =====================
    ; OVERLAYS
    ; =====================
    .IF gameState == STATE_TITLE
        ; Outer glow border
        invoke DrawRect, hdc, 140, 120, 520, 380, COLOR_YELLOW
        ; Main panel
        invoke DrawRect, hdc, 144, 124, 512, 372, COLOR_BLACK
        ; Inner accent line top
        invoke DrawRect, hdc, 148, 128, 504, 4, COLOR_YELLOW
        ; Inner accent line bottom
        invoke DrawRect, hdc, 148, 488, 504, 4, COLOR_YELLOW
        ; Inner accent line left
        invoke DrawRect, hdc, 148, 128, 4, 364, COLOR_YELLOW
        ; Inner accent line right
        invoke DrawRect, hdc, 648, 128, 4, 364, COLOR_YELLOW

        ; Title background flash strip
        invoke DrawRect, hdc, 148, 148, 504, 60, 00003060h

        ; Title text
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.left, 140
        mov rcT.right, 660
        mov rcT.top, 152
        mov rcT.bottom, 208
        invoke DrawTextA, hdc, ADDR szTitle, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Divider line under title
        invoke DrawRect, hdc, 200, 212, 400, 3, COLOR_YELLOW

        ; Controls header
        invoke SetTextColor, hdc, COLOR_CYAN
        mov rcT.top, 225
        mov rcT.bottom, 255
        invoke DrawTextA, hdc, ADDR szControls1, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 262
        mov rcT.bottom, 292
        invoke DrawTextA, hdc, ADDR szControls2, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Divider line above start
        invoke DrawRect, hdc, 200, 300, 400, 3, COLOR_DARKGRAY

        ; Blinking PRESS ENTER text (uses animT)
        .IF animT == 1
            invoke SetTextColor, hdc, COLOR_GREEN
        .ELSE
            invoke SetTextColor, hdc, COLOR_YELLOW
        .ENDIF
        mov rcT.top, 310
        mov rcT.bottom, 355
        invoke DrawTextA, hdc, ADDR szStartMsg, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Best score on title screen
        invoke BestToStr
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.top, 362
        mov rcT.bottom, 392
        invoke DrawTextA, hdc, ADDR szBestScore, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
        mov rcT.top, 392
        mov rcT.bottom, 422
        invoke DrawTextA, hdc, ADDR szBestNum, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Preview car (centered)
        invoke DrawCar, hdc, 362, 450, COLOR_GREEN, 1

    .ELSEIF gameState == STATE_DEAD
        ; Outer red glow border
        invoke DrawRect, hdc, 170, 170, 460, 280, COLOR_RED
        ; Main dark panel
        invoke DrawRect, hdc, 174, 174, 452, 272, COLOR_BLACK
        ; Dark red inner fill
        invoke DrawRect, hdc, 178, 178, 444, 264, 00100020h

        ; Top accent stripe
        invoke DrawRect, hdc, 178, 178, 444, 5, COLOR_RED
        ; Bottom accent stripe
        invoke DrawRect, hdc, 178, 437, 444, 5, COLOR_RED
        ; Left accent stripe
        invoke DrawRect, hdc, 178, 178, 5, 264, COLOR_RED
        ; Right accent stripe
        invoke DrawRect, hdc, 617, 178, 5, 264, COLOR_RED

        ; GAME OVER header strip
        invoke DrawRect, hdc, 183, 183, 434, 55, 00000040h

        ; GAME OVER text
        invoke SetTextColor, hdc, COLOR_RED
        mov rcT.left, 170
        mov rcT.right, 630
        mov rcT.top, 188
        mov rcT.bottom, 238
        invoke DrawTextA, hdc, ADDR szGameOver, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Divider
        invoke DrawRect, hdc, 220, 242, 360, 3, COLOR_RED

        ; Final score label
        invoke ScoreToStr
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.top, 252
        mov rcT.bottom, 282
        invoke DrawTextA, hdc, ADDR szScore, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Final score number
        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 282
        mov rcT.bottom, 318
        invoke DrawTextA, hdc, ADDR szScoreNum, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Divider
        invoke DrawRect, hdc, 220, 322, 360, 3, COLOR_DARKGRAY

        ; Best score
        invoke BestToStr
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.top, 330
        mov rcT.bottom, 358
        invoke DrawTextA, hdc, ADDR szBestScore, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 358
        mov rcT.bottom, 386
        invoke DrawTextA, hdc, ADDR szBestNum, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

        ; Blinking restart message
        .IF animT == 1
            invoke SetTextColor, hdc, COLOR_GREEN
        .ELSE
            invoke SetTextColor, hdc, COLOR_YELLOW
        .ENDIF
        mov rcT.top, 394
        mov rcT.bottom, 430
        invoke DrawTextA, hdc, ADDR szRestart, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE

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

