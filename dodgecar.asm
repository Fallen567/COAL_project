.386
.model flat, stdcall
option casemap :none
 
; Includes
include C:\masm32\include\windows.inc
include C:\masm32\include\kernel32.inc
include C:\masm32\include\user32.inc
include C:\masm32\include\gdi32.inc
include C:\masm32\include\winmm.inc
 
includelib C:\masm32\lib\kernel32.lib
includelib C:\masm32\lib\user32.lib
includelib C:\masm32\lib\gdi32.lib
includelib C:\masm32\lib\winmm.lib
 
; --------------------------------
; Constants
; --------------------------------
MAX_ENEMIES        EQU 16
MAX_STARS          EQU 80
MAX_EXPLOSIONS     EQU 10
 
SCREEN_WIDTH  EQU 800
SCREEN_HEIGHT EQU 600
 
ROAD_LEFT   EQU 100
ROAD_RIGHT  EQU 700
ROAD_WIDTH  EQU 600
 
LANE1_X  EQU 112
LANE2_X  EQU 262
LANE3_X  EQU 412
LANE4_X  EQU 562
LANE_WIDTH EQU 150
 
PLAYER_WIDTH  EQU 76
PLAYER_HEIGHT EQU 120
ENEMY_WIDTH   EQU 76
ENEMY_HEIGHT  EQU 120
 
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
    lane     DWORD ?
    carColor DWORD ?
Enemy ENDS
 
Star STRUCT
    posx    DWORD ?
    posy    DWORD ?
    speed   DWORD ?
    isLine  DWORD ?
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
szScoreNum   db 11 dup(0)
szBestScore  db "BEST:  ",0
szBestNum    db 11 dup(0)
 
gameState   DWORD STATE_TITLE
frameCount  DWORD 0
 
; -------------------------------------------------------
; SOUND FIX:
;   crashSoundPlayed  - set to 1 the moment we trigger
;                       the crash so it never fires twice
;   crashSoundTimer   - counts down frames; while > 0
;                       we keep the audio thread alive by
;                       NOT calling PlaySoundA again.
;                       When it hits 0 we are done.
; -------------------------------------------------------
crashSoundPlayed  DWORD 0
crashSoundTimer   DWORD 0
 
playerLane    DWORD 1
playerX       DWORD LANE2_X
playerY       DWORD 450
laneMoving    DWORD 0
laneTargetX   DWORD LANE2_X
laneSpeed     DWORD 14
moveCooldown  DWORD 0
 
score         DWORD 0
bestScore     DWORD 0
carsPassed    DWORD 0
 
spawnTimer    DWORD 0
spawnInterval DWORD 60
gameSpeed     DWORD 10
scoreFlashTimer DWORD 0
 
randSeed DWORD 87654321h
 
; -------------------------------------------------------
; SOUND FIX: lane sound uses SND_ASYNC as before.
; crash sound uses SND_SYNC so it cannot be cut off by
; anything.  We fire it from a dedicated PlayCrashSound
; proc that is called ONCE and guards itself with
; crashSoundPlayed.
; -------------------------------------------------------
szLaneSound  db "assalamualaikum_edit-volume-adjusted.wav",0
szCrashSound db "shitman-volume-adjusted.wav",0
 
 
; --------------------------------
.CODE
 
WinMain PROTO :DWORD,:DWORD,:DWORD,:DWORD
WndProc PROTO :DWORD,:DWORD,:DWORD,:DWORD
 
; -------------------------------------------------------
; PlayCrashSound
;   Guaranteed-once crash audio.
;   1. Stops whatever is playing (lane sound or silence).
;   2. Plays crash WAV synchronously so the OS cannot
;      pre-empt it with another async sound.
;   3. Sets crashSoundPlayed=1 so this proc is a no-op
;      on every subsequent call in the same game round.
; -------------------------------------------------------
PlayCrashSound PROC
    cmp crashSoundPlayed, 1
    je  pcs_done
 
    ; Stop any currently playing async sound (lane change etc.)
    invoke PlaySoundA, NULL, NULL, 0
 
    ; Play crash sound — SND_SYNC blocks until it finishes,
    ; meaning it cannot be interrupted or overwritten.
    invoke PlaySoundA, ADDR szCrashSound, NULL, SND_SYNC or SND_FILENAME
 
    mov crashSoundPlayed, 1
 
pcs_done:
    ret
PlayCrashSound ENDP
 
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
 
; --- Score to string ---
ScoreToStr PROC USES eax ebx ecx edx edi
    lea edi, szScoreNum
    mov ecx, 10
    mov al, ' '
    rep stosb
    mov byte ptr [edi], 0
    mov eax, score
    lea edi, szScoreNum
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
ScoreToStr ENDP
 
BestToStr PROC USES eax ebx ecx edx edi
    lea edi, szBestNum
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
 
; --- Lane number → pixel X ---
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
    invoke RandomRange, 4
    mov [esi].Enemy.lane, eax
    invoke LaneToX, eax
    mov [esi].Enemy.posx, eax
    mov [esi].Enemy.posy, -130
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
    ; -------------------------------------------------------
    ; SOUND FIX: reset both sound guards on new game
    ; -------------------------------------------------------
    mov crashSoundPlayed, 0
    mov crashSoundTimer,  0
 
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
 
    mov esi, OFFSET enemyArr
    mov ecx, MAX_ENEMIES
clr_e:
    mov [esi].Enemy.isActive, 0
    add esi, TYPE Enemy
    dec ecx
    jnz clr_e
 
    mov esi, OFFSET explosionArr
    mov ecx, MAX_EXPLOSIONS
clr_x:
    mov [esi].Explosion.isActive, 0
    add esi, TYPE Explosion
    dec ecx
    jnz clr_x
 
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
    mov ebx, 0
init_st:
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
    mov [esi].Star.speed, 0
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
 
    invoke GetAsyncKeyState, VK_LEFT
    test eax, 8000h
    jz chk_right
 
    mov eax, playerLane
    cmp eax, 0
    jle chk_right
 
    dec playerLane
    invoke LaneToX, playerLane
    mov laneTargetX, eax
    mov laneMoving, 1
 
    invoke PlaySoundA, ADDR szLaneSound, NULL, SND_ASYNC or SND_FILENAME
 
    mov moveCooldown, 12
    jmp update_move
 
chk_right:
    invoke GetAsyncKeyState, VK_RIGHT
    test eax, 8000h
    jz update_move
 
    mov eax, playerLane
    cmp eax, 3
    jge update_move
 
    inc playerLane
    invoke LaneToX, playerLane
    mov laneTargetX, eax
    mov laneMoving, 1
 
    invoke PlaySoundA, ADDR szLaneSound, NULL, SND_ASYNC or SND_FILENAME
 
    mov moveCooldown, 12
 
dec_cd:
    dec moveCooldown
 
update_move:
    cmp laneMoving, 1
    jne done
 
    mov eax, playerX
    mov ebx, laneTargetX
 
    cmp eax, ebx
    jl move_right
    jg move_left
 
    mov laneMoving, 0
    jmp done
 
move_right:
    add eax, laneSpeed
    cmp eax, ebx
    jl store_x
    mov eax, ebx
    mov laneMoving, 0
    jmp store_x
 
move_left:
    sub eax, laneSpeed
    cmp eax, ebx
    jg store_x
    mov eax, ebx
    mov laneMoving, 0
 
store_x:
    mov playerX, eax
 
done:
    ret
UpdatePlayer ENDP
 
UpdateEnemies PROC USES esi ecx
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
 
    mov eax, gameSpeed
    add [esi].Enemy.posy, eax
 
    mov eax, [esi].Enemy.posy
    cmp eax, SCREEN_HEIGHT
    jl ue_nx
 
    mov [esi].Enemy.isActive, 0
 
    inc carsPassed
    inc score
    mov scoreFlashTimer, 6
 
    mov eax, carsPassed
    xor edx, edx
    mov ecx, 10
    div ecx
    cmp edx, 0
    jne ue_nx
 
    mov eax, gameSpeed
    cmp eax, 30
    jge skip_speed
    add gameSpeed, 2
skip_speed:
 
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
 
; -------------------------------------------------------
; CheckCollisions
;   On hit: spawn explosion, call PlayCrashSound (once),
;           set STATE_DEAD, update best score.
; -------------------------------------------------------
CheckCollisions PROC USES esi ecx
    cmp gameState, STATE_PLAY
    jne cc_done
 
    mov esi, OFFSET enemyArr
    mov ecx, MAX_ENEMIES
 
cc_lp:
    cmp [esi].Enemy.isActive, 0
    je cc_nx
 
    mov eax, playerX
    add eax, PLAYER_WIDTH
    cmp eax, [esi].Enemy.posx
    jle cc_nx
 
    mov eax, [esi].Enemy.posx
    add eax, ENEMY_WIDTH
    cmp eax, playerX
    jle cc_nx
 
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
 
    ; ---- COLLISION ----
    invoke SpawnExplosion, playerX, playerY
 
    ; -------------------------------------------------------
    ; SOUND FIX: call our guaranteed-once crash sound proc.
    ; It stops any async lane sound first, then plays the
    ; crash WAV with SND_SYNC so nothing can cut it off.
    ; -------------------------------------------------------
    call PlayCrashSound
 
    mov gameState, STATE_DEAD
 
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
 
    invoke DrawRect, hdc, posX, posY, ENEMY_WIDTH, ENEMY_HEIGHT, bodyCol
 
    invoke DrawRect, hdc, posX, posY, 4, ENEMY_HEIGHT, COLOR_DARKGRAY
    mov eax, posX
    add eax, ENEMY_WIDTH
    sub eax, 4
    invoke DrawRect, hdc, eax, posY, 4, ENEMY_HEIGHT, COLOR_DARKGRAY
 
    mov eax, posX
    add eax, 10
    mov ebx, posY
    add ebx, 24
    invoke DrawRect, hdc, eax, ebx, 56, 50, COLOR_DARKGRAY
 
    mov eax, posX
    add eax, 14
    mov ebx, posY
    add ebx, 27
    invoke DrawRect, hdc, eax, ebx, 48, 8, 00606060h
 
    mov eax, posX
    add eax, 4
    mov ebx, posY
    add ebx, 74
    invoke DrawRect, hdc, eax, ebx, 68, 3, COLOR_DARKGRAY
 
    mov eax, posX
    add eax, 8
    mov ebx, posY
    add ebx, 79
    invoke DrawRect, hdc, eax, ebx, 14, 4, COLOR_LIGHTGRAY
 
    mov eax, posX
    add eax, 54
    mov ebx, posY
    add ebx, 79
    invoke DrawRect, hdc, eax, ebx, 14, 4, COLOR_LIGHTGRAY
 
    .IF isPlayer == 1
        mov eax, posX
        add eax, 13
        mov ebx, posY
        add ebx, 10
        invoke DrawRect, hdc, eax, ebx, 50, 20, COLOR_CYAN
 
        mov eax, posX
        add eax, 13
        mov ebx, posY
        add ebx, 88
        invoke DrawRect, hdc, eax, ebx, 50, 18, COLOR_CYAN
    .ELSE
        mov eax, posX
        add eax, 13
        mov ebx, posY
        add ebx, 88
        invoke DrawRect, hdc, eax, ebx, 50, 18, COLOR_CYAN
 
        mov eax, posX
        add eax, 13
        mov ebx, posY
        add ebx, 10
        invoke DrawRect, hdc, eax, ebx, 50, 20, COLOR_CYAN
    .ENDIF
 
    .IF isPlayer == 1
        mov eax, posX
        add eax, 5
        mov ebx, posY
        add ebx, 4
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_YELLOW
        mov eax, posX
        add eax, 7
        mov ebx, posY
        add ebx, 5
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_WHITE
 
        mov eax, posX
        add eax, 49
        mov ebx, posY
        add ebx, 4
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_YELLOW
        mov eax, posX
        add eax, 51
        mov ebx, posY
        add ebx, 5
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_WHITE
 
        mov eax, posX
        add eax, 5
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 12
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_RED
        mov eax, posX
        add eax, 7
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 10
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_DARKRED
 
        mov eax, posX
        add eax, 49
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 12
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_RED
        mov eax, posX
        add eax, 51
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 10
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_DARKRED
    .ELSE
        mov eax, posX
        add eax, 5
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 12
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_YELLOW
        mov eax, posX
        add eax, 7
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 10
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_WHITE
 
        mov eax, posX
        add eax, 49
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 12
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_YELLOW
        mov eax, posX
        add eax, 51
        mov ebx, posY
        add ebx, ENEMY_HEIGHT
        sub ebx, 10
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_WHITE
 
        mov eax, posX
        add eax, 5
        mov ebx, posY
        add ebx, 4
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_RED
        mov eax, posX
        add eax, 7
        mov ebx, posY
        add ebx, 5
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_DARKRED
 
        mov eax, posX
        add eax, 49
        mov ebx, posY
        add ebx, 4
        invoke DrawRect, hdc, eax, ebx, 22, 8, COLOR_RED
        mov eax, posX
        add eax, 51
        mov ebx, posY
        add ebx, 5
        invoke DrawRect, hdc, eax, ebx, 18, 5, COLOR_DARKRED
    .ENDIF
 
    mov eax, posX
    sub eax, 8
    mov ebx, posY
    add ebx, 8
    invoke DrawRect, hdc, eax, ebx, 12, 28, COLOR_BLACK
 
    mov eax, posX
    add eax, ENEMY_WIDTH
    sub eax, 4
    mov ebx, posY
    add ebx, 8
    invoke DrawRect, hdc, eax, ebx, 12, 28, COLOR_BLACK
 
    mov eax, posX
    sub eax, 8
    mov ebx, posY
    add ebx, ENEMY_HEIGHT
    sub ebx, 36
    invoke DrawRect, hdc, eax, ebx, 12, 28, COLOR_BLACK
 
    mov eax, posX
    add eax, ENEMY_WIDTH
    sub eax, 4
    mov ebx, posY
    add ebx, ENEMY_HEIGHT
    sub ebx, 36
    invoke DrawRect, hdc, eax, ebx, 12, 28, COLOR_BLACK
 
    mov eax, posX
    add eax, 34
    mov ebx, posY
    add ebx, 2
    invoke DrawRect, hdc, eax, ebx, 8, 10, COLOR_LIGHTGRAY
 
    ret
DrawCar ENDP
 
UpdateGame PROC
    inc frameCount
 
    cmp scoreFlashTimer, 0
    jle no_flash_dec
    dec scoreFlashTimer
no_flash_dec:
 
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
 
    mov rcT.left, 0
    mov rcT.right, SCREEN_WIDTH
 
    ; ---- Background ----
    invoke DrawRect, hdc, 0, 0, ROAD_LEFT, SCREEN_HEIGHT, COLOR_GRASS
    invoke DrawRect, hdc, ROAD_RIGHT, 0, 100, SCREEN_HEIGHT, COLOR_GRASS
 
    invoke DrawRect, hdc, 8,  0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 22, 0, 3, SCREEN_HEIGHT, 00185018h
    invoke DrawRect, hdc, 40, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 55, 0, 3, SCREEN_HEIGHT, 00185018h
    invoke DrawRect, hdc, 70, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
 
    invoke DrawRect, hdc, 716, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 730, 0, 3, SCREEN_HEIGHT, 00185018h
    invoke DrawRect, hdc, 748, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
    invoke DrawRect, hdc, 763, 0, 3, SCREEN_HEIGHT, 00185018h
    invoke DrawRect, hdc, 778, 0, 6, SCREEN_HEIGHT, COLOR_DARKGREEN
 
    invoke DrawRect, hdc, ROAD_LEFT, 0, ROAD_WIDTH, SCREEN_HEIGHT, COLOR_ROAD
    invoke DrawRect, hdc, ROAD_LEFT, 0, 8, SCREEN_HEIGHT, 00202020h
    invoke DrawRect, hdc, ROAD_RIGHT-8, 0, 8, SCREEN_HEIGHT, 00202020h
    invoke DrawRect, hdc, ROAD_LEFT,   0, 5, SCREEN_HEIGHT, COLOR_WHITE
    invoke DrawRect, hdc, ROAD_RIGHT-5, 0, 5, SCREEN_HEIGHT, COLOR_WHITE
 
    ; Curb stripes left
    mov esi, OFFSET starArr
    mov ecx, MAX_STARS
crb_lp:
    push ecx
    mov eax, [esi].Star.posy
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
 
    ; Dashed lane dividers
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
 
    ; ---- Game objects ----
    .IF gameState != STATE_TITLE
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
 
        .IF gameState != STATE_DEAD
            invoke DrawCar, hdc, playerX, playerY, COLOR_GREEN, 1
        .ENDIF
 
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
 
    ; ---- HUD ----
    invoke SetBkMode, hdc, TRANSPARENT
 
    invoke DrawRect, hdc, 0, 0, 240, 80, COLOR_YELLOW
    invoke DrawRect, hdc, 3, 3, 234, 74, 00101010h
    invoke DrawRect, hdc, 3, 3, 234, 6, COLOR_YELLOW
 
    .IF gameState == STATE_PLAY || gameState == STATE_DEAD
        invoke SetTextColor, hdc, COLOR_CYAN
        mov rcT.left, 10
        mov rcT.right, 120
        mov rcT.top, 10
        mov rcT.bottom, 35
        invoke DrawTextA, hdc, ADDR szScore, -1, ADDR rcT, DT_LEFT or DT_SINGLELINE
 
        invoke ScoreToStr
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
 
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.left, 10
        mov rcT.right, 120
        mov rcT.top, 40
        mov rcT.bottom, 65
        invoke DrawTextA, hdc, ADDR szBestScore, -1, ADDR rcT, DT_LEFT or DT_SINGLELINE
 
        invoke BestToStr
        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.left, 100
        mov rcT.right, 230
        invoke DrawTextA, hdc, ADDR szBestNum, -1, ADDR rcT, DT_LEFT or DT_SINGLELINE
 
        mov rcT.left, 0
        mov rcT.right, SCREEN_WIDTH
    .ENDIF
 
    ; ---- Overlays ----
    .IF gameState == STATE_TITLE
        invoke DrawRect, hdc, 140, 120, 520, 380, COLOR_YELLOW
        invoke DrawRect, hdc, 144, 124, 512, 372, COLOR_BLACK
        invoke DrawRect, hdc, 148, 128, 504, 4, COLOR_YELLOW
        invoke DrawRect, hdc, 148, 488, 504, 4, COLOR_YELLOW
        invoke DrawRect, hdc, 148, 128, 4, 364, COLOR_YELLOW
        invoke DrawRect, hdc, 648, 128, 4, 364, COLOR_YELLOW
        invoke DrawRect, hdc, 148, 148, 504, 60, 00003060h
 
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.left, 140
        mov rcT.right, 660
        mov rcT.top, 152
        mov rcT.bottom, 208
        invoke DrawTextA, hdc, ADDR szTitle, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
        invoke DrawRect, hdc, 200, 212, 400, 3, COLOR_YELLOW
 
        invoke SetTextColor, hdc, COLOR_CYAN
        mov rcT.top, 225
        mov rcT.bottom, 255
        invoke DrawTextA, hdc, ADDR szControls1, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 262
        mov rcT.bottom, 292
        invoke DrawTextA, hdc, ADDR szControls2, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
        invoke DrawRect, hdc, 200, 300, 400, 3, COLOR_DARKGRAY
 
        .IF animT == 1
            invoke SetTextColor, hdc, COLOR_GREEN
        .ELSE
            invoke SetTextColor, hdc, COLOR_YELLOW
        .ENDIF
        mov rcT.top, 310
        mov rcT.bottom, 355
        invoke DrawTextA, hdc, ADDR szStartMsg, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
        invoke BestToStr
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.top, 362
        mov rcT.bottom, 392
        invoke DrawTextA, hdc, ADDR szBestScore, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
        mov rcT.top, 392
        mov rcT.bottom, 422
        invoke DrawTextA, hdc, ADDR szBestNum, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
        invoke DrawCar, hdc, 362, 450, COLOR_GREEN, 1
 
    .ELSEIF gameState == STATE_DEAD
        invoke DrawRect, hdc, 170, 170, 460, 280, COLOR_RED
        invoke DrawRect, hdc, 174, 174, 452, 272, COLOR_BLACK
        invoke DrawRect, hdc, 178, 178, 444, 264, 00100020h
        invoke DrawRect, hdc, 178, 178, 444, 5, COLOR_RED
        invoke DrawRect, hdc, 178, 437, 444, 5, COLOR_RED
        invoke DrawRect, hdc, 178, 178, 5, 264, COLOR_RED
        invoke DrawRect, hdc, 617, 178, 5, 264, COLOR_RED
        invoke DrawRect, hdc, 183, 183, 434, 55, 00000040h
 
        invoke SetTextColor, hdc, COLOR_RED
        mov rcT.left, 170
        mov rcT.right, 630
        mov rcT.top, 188
        mov rcT.bottom, 238
        invoke DrawTextA, hdc, ADDR szGameOver, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
        invoke DrawRect, hdc, 220, 242, 360, 3, COLOR_RED
 
        invoke ScoreToStr
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.top, 252
        mov rcT.bottom, 282
        invoke DrawTextA, hdc, ADDR szScore, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 282
        mov rcT.bottom, 318
        invoke DrawTextA, hdc, ADDR szScoreNum, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
        invoke DrawRect, hdc, 220, 322, 360, 3, COLOR_DARKGRAY
 
        invoke BestToStr
        invoke SetTextColor, hdc, COLOR_YELLOW
        mov rcT.top, 330
        mov rcT.bottom, 358
        invoke DrawTextA, hdc, ADDR szBestScore, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
        invoke SetTextColor, hdc, COLOR_WHITE
        mov rcT.top, 358
        mov rcT.bottom, 386
        invoke DrawTextA, hdc, ADDR szBestNum, -1, ADDR rcT, DT_CENTER or DT_VCENTER or DT_SINGLELINE
 
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