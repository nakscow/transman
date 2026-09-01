#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; =====================================================================
; MapOverlay - Emme4 네트워크 편집용 반투명 지도 오버레이
;
; 사용법:
;   1. 이 스크립트를 더블클릭해서 실행
;   2. 처음 실행 시 지도 이미지 파일을 선택
;   3. Ctrl+Alt+T 로 "편집 모드"와 "클릭 통과(Emme4 조작) 모드"를 전환
;      - 클릭 통과 모드: 오버레이가 마우스/키보드 입력을 그대로 Emme4로 흘려보냄
;      - 편집 모드     : 오버레이 이미지를 드래그로 이동, 휠로 확대/축소, 투명도 조절 가능
;
; 단축키 (모두 편집 모드에서만 동작):
;   Ctrl+Alt+T        : 편집 모드 <-> 클릭 통과 모드 전환
;   Shift + 마우스휠  : 확대/축소
;   좌클릭 드래그      : 이미지(창) 이동
;   Ctrl+Alt+Up/Down  : 투명도 증가/감소
;   Ctrl+Alt+O        : 다른 지도 이미지로 교체
;   Ctrl+Alt+Q        : 설정 저장 후 종료
; =====================================================================

CONFIG_FILE := A_ScriptDir "\MapOverlay.ini"

; ---- 전역 상태 ----
mapGui   := ""
pic      := ""
imgPath  := ""
baseW    := 0
baseH    := 0
scale    := 1.0
posX     := 100
posY     := 100
opacity  := 150      ; 0(완전 투명) ~ 255(불투명)
editMode := true     ; 시작 시에는 위치/배율을 맞출 수 있도록 편집 모드로 시작

; =====================================================================
; 시작 절차
; =====================================================================
LoadSettings()

if (imgPath = "" || !FileExist(imgPath)) {
    imgPath := SelectImage()
    if (imgPath = "")
        ExitApp()
}

CreateOverlay()
OnMessage(0x0201, OnLButtonDown)   ; WM_LBUTTONDOWN - 드래그 이동용
OnExit(OnScriptExit)

ApplyEditMode()
ShowStatus("MapOverlay 시작 (Ctrl+Alt+T: 편집/클릭통과 전환, Ctrl+Alt+Q: 종료)")

; =====================================================================
; 오버레이 창 생성
; =====================================================================
CreateOverlay() {
    global mapGui, pic, imgPath, baseW, baseH, scale, posX, posY, opacity

    mapGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "MapOverlay")
    mapGui.BackColor := "White"

    ; 화면 폭의 60%를 기준 폭으로 잡고, 이미지는 원본 비율을 유지하며 리사이즈됨
    defaultW := Round(A_ScreenWidth * 0.6)
    pic := mapGui.Add("Picture", "x0 y0 w" defaultW, imgPath)
    pic.GetPos(&px, &py, &pw, &ph)
    baseW := pw
    baseH := ph

    if (scale <= 0)
        scale := 1.0

    w := Round(baseW * scale)
    h := Round(baseH * scale)
    if (w < 20 || h < 20) {
        w := baseW, h := baseH, scale := 1.0
    }
    pic.Move(0, 0, w, h)

    mapGui.Show("x" posX " y" posY " w" w " h" h " NoActivate")
    WinSetTransparent(opacity, "ahk_id " mapGui.Hwnd)
}

; =====================================================================
; 편집 모드 <-> 클릭 통과 모드
; =====================================================================
ToggleClickThrough(*) {
    global editMode
    editMode := !editMode
    if (editMode)
        ApplyEditMode()
    else
        ApplyClickThrough()
}

^!t:: ToggleClickThrough()

ApplyClickThrough() {
    global mapGui
    WinSetExStyle("+0x20", "ahk_id " mapGui.Hwnd)   ; WS_EX_TRANSPARENT: 마우스 클릭이 아래 창(Emme4)으로 통과
    ShowStatus("오버레이 비활성화 (Emme4 조작 가능) - Ctrl+Alt+T로 편집 복귀")
}

ApplyEditMode() {
    global mapGui
    WinSetExStyle("-0x20", "ahk_id " mapGui.Hwnd)   ; 클릭을 오버레이가 다시 받음
    ShowStatus("오버레이 편집 모드 (드래그 이동 / Shift+휠 확대축소 / Ctrl+Alt+Up,Down 투명도)")
}

; =====================================================================
; 드래그로 창 이동 (편집 모드에서만)
; =====================================================================
OnLButtonDown(wParam, lParam, msg, hwnd) {
    global editMode, pic, mapGui
    if (!editMode)
        return
    if (hwnd != pic.Hwnd)
        return
    PostMessage(0xA1, 2, , , "ahk_id " mapGui.Hwnd)   ; WM_NCLBUTTONDOWN + HTCAPTION
}

; =====================================================================
; 확대 / 축소 (Shift + 마우스 휠, 편집 모드에서만)
; =====================================================================
~+WheelUp:: ZoomStep(1)
~+WheelDown:: ZoomStep(-1)

ZoomStep(direction) {
    global editMode, scale
    if (!editMode)
        return
    newScale := scale + (0.05 * direction)
    if (newScale < 0.1)
        newScale := 0.1
    if (newScale > 5.0)
        newScale := 5.0
    scale := newScale
    ResizeOverlay()
}

ResizeOverlay() {
    global mapGui, pic, baseW, baseH, scale
    w := Round(baseW * scale)
    h := Round(baseH * scale)
    pic.Move(0, 0, w, h)
    mapGui.Move(, , w, h)
    ShowStatus("배율: " Round(scale * 100) "%")
}

; =====================================================================
; 투명도 조절
; =====================================================================
^!Up:: AdjustOpacity(15)
^!Down:: AdjustOpacity(-15)

AdjustOpacity(delta) {
    global editMode, opacity, mapGui
    if (!editMode)
        return
    opacity += delta
    if (opacity < 20)
        opacity := 20
    if (opacity > 255)
        opacity := 255
    WinSetTransparent(opacity, "ahk_id " mapGui.Hwnd)
    ShowStatus("투명도: " Round(opacity / 255 * 100) "%")
}

; =====================================================================
; 지도 이미지 교체
; =====================================================================
^!o:: ChangeImage()

ChangeImage(*) {
    global editMode, imgPath, mapGui, posX, posY, scale, opacity
    if (!editMode) {
        ShowStatus("이미지 교체는 편집 모드에서만 가능합니다 (Ctrl+Alt+T)")
        return
    }
    newPath := SelectImage()
    if (newPath = "")
        return
    mapGui.GetPos(&x, &y)
    posX := x, posY := y
    imgPath := newPath
    scale := 1.0
    mapGui.Destroy()
    CreateOverlay()
    ApplyEditMode()
    ShowStatus("이미지 교체됨: " imgPath)
}

SelectImage() {
    return FileSelect(1, , "지도 이미지 선택", "이미지 (*.png; *.jpg; *.jpeg; *.bmp; *.gif)")
}

; =====================================================================
; 종료 및 설정 저장
; =====================================================================
^!q:: ExitApp()

OnScriptExit(*) {
    SaveSettings()
}

LoadSettings() {
    global imgPath, scale, posX, posY, opacity, CONFIG_FILE
    if !FileExist(CONFIG_FILE)
        return
    imgPath := IniRead(CONFIG_FILE, "Overlay", "ImagePath", "")
    scale   := IniRead(CONFIG_FILE, "Overlay", "Scale", "1.0") + 0
    posX    := IniRead(CONFIG_FILE, "Overlay", "PosX", "100") + 0
    posY    := IniRead(CONFIG_FILE, "Overlay", "PosY", "100") + 0
    opacity := IniRead(CONFIG_FILE, "Overlay", "Opacity", "150") + 0
}

SaveSettings() {
    global imgPath, scale, mapGui, opacity, CONFIG_FILE
    if (mapGui != "") {
        mapGui.GetPos(&x, &y)
        IniWrite(x, CONFIG_FILE, "Overlay", "PosX")
        IniWrite(y, CONFIG_FILE, "Overlay", "PosY")
    }
    IniWrite(imgPath, CONFIG_FILE, "Overlay", "ImagePath")
    IniWrite(scale, CONFIG_FILE, "Overlay", "Scale")
    IniWrite(opacity, CONFIG_FILE, "Overlay", "Opacity")
}

; =====================================================================
; 상태 표시 (화면 좌상단에 짧게 툴팁 표시)
; =====================================================================
ShowStatus(msg) {
    ToolTip(msg, 20, 20)
    SetTimer(() => ToolTip(), -1800)
}
