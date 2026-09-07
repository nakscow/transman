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
;      - 편집 모드     : 오버레이 위에서 드래그로 이동, 방향키로 미세 이동,
;                        Shift+휠로 커서 위치를 기준으로 확대/축소, 투명도 조절 가능
;
; 단축키 (표시/종료 관련은 언제나 동작, 나머지는 편집 모드에서만 동작):
;   Ctrl+Alt+T        : 편집 모드 <-> 클릭 통과 모드 전환 (언제나 동작)
;   Ctrl+Alt+H        : 오버레이 완전히 숨김 <-> 표시 전환 (언제나 동작)
;   좌클릭 드래그      : 오버레이 몸통을 클릭한 채로 끌면 그 위치로 이동 (편집 모드)
;   좌클릭 드래그(모서리) : 오버레이 모서리 근처를 클릭한 채로 끌면 비율을 유지하며
;                        크기 조정 (편집 모드, 반대쪽 모서리가 고정된 채로 커지고 작아짐)
;   방향키            : 오버레이 1px 미세 이동 (편집 모드)
;   Shift+방향키       : 오버레이 10px 이동 (편집 모드)
;   Shift + 마우스휠  : 마우스 커서 위치를 기준으로 확대/축소 (편집 모드)
;   Ctrl+Alt+Up/Down  : 투명도 증가/감소 (편집 모드)
;   Ctrl+Alt+O        : 다른 지도 이미지로 교체 (편집 모드)
;   Ctrl+Alt+R        : 참조점 기반 반자동 정렬 시작 (아래 참고)
;   Ctrl+Alt+Q        : 설정 저장 후 종료 (언제나 동작)
;
; 참조점 기반 반자동 정렬 (Ctrl+Alt+R):
;   지도 이미지와 Emme4 화면에서 같은 지점(예: 교차로) 2곳을 순서대로 클릭하면
;   두 기준점 사이 거리 비율로 배율과 이동량을 자동 계산해 오버레이를 맞춰줍니다.
;   1) 지도 이미지 위에서 기준점 1 클릭
;   2) 지도 이미지 위에서 기준점 2 클릭 (기준점 1과 멀리 떨어진 지점일수록 정확)
;   3) Emme4 화면에서 기준점 1과 동일한 지점 클릭
;   4) Emme4 화면에서 기준점 2와 동일한 지점 클릭 -> 자동 정렬 후 클릭 통과 모드로 전환
;   진행 중 Esc로 언제든 취소 가능
; =====================================================================

CONFIG_FILE := A_ScriptDir "\MapOverlay.ini"

; ---- 전역 상태 ----
mapGui         := ""
pic            := ""
imgPath        := ""
baseW          := 0
baseH          := 0
scale          := 1.0
posX           := 100
posY           := 100
opacity        := 150      ; 0(완전 투명) ~ 255(불투명)
editMode       := true     ; 시작 시에는 위치/배율을 맞출 수 있도록 편집 모드로 시작
overlayVisible := true
overlayReady   := false    ; CreateOverlay() 완료 전에는 모든 단축키가 무시됨(안전장치)
EDGE_MARGIN    := 14       ; 모서리 크기조정으로 인식할 가장자리 폭(px)

; ---- 참조점 정렬(Calibration) 상태 ----
; 0=대기, 1=이미지 기준점1 대기, 2=이미지 기준점2 대기, 3=화면 기준점1 대기, 4=화면 기준점2 대기
calibState    := 0
calibImgP1    := ""
calibImgP2    := ""
calibScreenP1 := ""
calibScreenP2 := ""

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
overlayReady := true
OnExit(OnScriptExit)

ApplyEditMode()
ShowStatus("MapOverlay 시작 (Ctrl+Alt+T: 편집/클릭통과, Ctrl+Alt+H: 숨김/표시, Ctrl+Alt+Q: 종료)")

; =====================================================================
; 오버레이 창 생성
; =====================================================================
CreateOverlay() {
    global mapGui, pic, imgPath, baseW, baseH, scale, posX, posY, opacity

    mapGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "MapOverlay")
    mapGui.BackColor := "White"

    ; 화면 폭의 60%를 기준 폭으로 잡고, 이미지는 원본 비율을 유지하며 리사이즈됨
    ; (h를 생략하면 GUI 기본 높이로 늘어나 비율이 깨지므로, "-1"로 비율 유지 자동계산을 명시해야 함)
    defaultW := Round(A_ScreenWidth * 0.6)
    pic := mapGui.Add("Picture", "x0 y0 w" defaultW " h-1", imgPath)
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
    if (w != pw || h != ph)
        ReloadPicAtSize(w, h)

    mapGui.Show("x" posX " y" posY " w" w " h" h " NoActivate")
    WinSetTransparent(opacity, "ahk_id " mapGui.Hwnd)
}

; Picture 컨트롤을 Move()로 리사이즈하면 기존 비트맵을 다시 그리지 않고 가장자리를
; 늘려서 채우는 경우가 있어(확대 시 가장자리가 복제된 것처럼 보이는 현상), 배율이
; 바뀔 때마다 컨트롤을 새로 만들어 이미지를 해당 크기로 다시 로드/렌더링한다.
ReloadPicAtSize(w, h) {
    global mapGui, pic, imgPath
    pic.Destroy()
    pic := mapGui.Add("Picture", "x0 y0 w" w " h" h, imgPath)
}

; =====================================================================
; 오버레이 위에 좌표가 있는지 판정 (드래그/기준점 클릭 판정에 공통 사용)
; =====================================================================
IsOverOverlay(mx, my) {
    global mapGui
    mapGui.GetPos(&wx, &wy, &ww, &wh)
    return (mx >= wx && mx < wx + ww && my >= wy && my < wy + wh)
}

; =====================================================================
; 편집 모드 <-> 클릭 통과 모드
; =====================================================================
ToggleClickThrough(*) {
    global editMode, calibState, overlayReady
    if (!overlayReady)
        return
    if (calibState != 0)
        CancelCalibration()
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
    ShowStatus("오버레이 편집 모드 (드래그/방향키 이동, Shift+휠 확대축소, Ctrl+Alt+Up/Down 투명도)")
}

; =====================================================================
; 완전 숨김 <-> 표시 (전용 토글 단축키)
; =====================================================================
^!h:: ToggleVisibility()

ToggleVisibility(*) {
    global mapGui, overlayVisible, calibState, overlayReady
    if (!overlayReady)
        return
    if (calibState != 0)
        CancelCalibration()
    overlayVisible := !overlayVisible
    if (overlayVisible) {
        mapGui.Show("NoActivate")
        ShowStatus("오버레이 표시")
    } else {
        mapGui.Hide()
        ShowStatus("오버레이 숨김 (Ctrl+Alt+H로 다시 표시)")
    }
}

; =====================================================================
; 좌클릭 처리: 드래그 이동 / 정렬 모드의 기준점 캡처
; =====================================================================
~LButton:: HandleLButton()

HandleLButton(*) {
    global editMode, calibState, calibImgP1, calibImgP2, calibScreenP1, calibScreenP2, scale, mapGui, overlayReady
    if (!overlayReady)
        return

    MouseGetPos(&mx, &my)

    ; --- 정렬 1/4, 2/4: 지도 이미지 위 기준점 클릭 ---
    if (calibState = 1 || calibState = 2) {
        if (!IsOverOverlay(mx, my)) {
            ShowStatus("지도 이미지 위를 클릭해주세요")
            return
        }
        mapGui.GetPos(&wx, &wy)
        ; 현재 배율을 반영해 "배율 1배 기준" 이미지 좌표로 환산 (기준점끼리 같은 좌표계여야 함)
        baseX := (mx - wx) / scale
        baseY := (my - wy) / scale

        if (calibState = 1) {
            calibImgP1 := [baseX, baseY]
            calibState := 2
            ShowStatus("정렬 2/4: 지도 이미지에서 기준점 2를 클릭하세요 (기준점 1과 먼 지점일수록 정확)")
        } else {
            calibImgP2 := [baseX, baseY]
            calibState := 3
            editMode := false
            ApplyClickThrough()
            ShowStatus("정렬 3/4: Emme4 화면에서 기준점 1과 같은 지점을 클릭하세요")
        }
        return
    }

    ; --- 정렬 3/4, 4/4: Emme4 화면 위 기준점 클릭 (클릭은 그대로 Emme4로도 전달됨) ---
    if (calibState = 3) {
        calibScreenP1 := [mx, my]
        calibState := 4
        ShowStatus("정렬 4/4: Emme4 화면에서 기준점 2와 같은 지점을 클릭하세요")
        return
    }
    if (calibState = 4) {
        calibScreenP2 := [mx, my]
        calibState := 0
        ApplyCalibration()
        return
    }

    ; --- 일반 드래그 이동 / 모서리 크기조정: 편집 모드이고, 오버레이 위에서 클릭했을 때만 ---
    if (!editMode)
        return
    if (!IsOverOverlay(mx, my))
        return

    corner := GetResizeCorner(mx, my)
    if (corner != "")
        ResizeFromCorner(corner, mx, my)
    else
        DragOverlay(mx, my)
}

; 클릭 좌표가 오버레이의 어느 모서리(가장자리 EDGE_MARGIN px 이내)에 있는지 판정.
; 모서리가 아니면 빈 문자열을 반환(=몸통 클릭, 이동으로 처리).
GetResizeCorner(mx, my) {
    global mapGui, EDGE_MARGIN
    mapGui.GetPos(&wx, &wy, &ww, &wh)

    nearLeft   := (mx - wx) <= EDGE_MARGIN
    nearRight  := (wx + ww - mx) <= EDGE_MARGIN
    nearTop    := (my - wy) <= EDGE_MARGIN
    nearBottom := (wy + wh - my) <= EDGE_MARGIN

    if (nearLeft && nearTop)
        return "TL"
    if (nearRight && nearTop)
        return "TR"
    if (nearLeft && nearBottom)
        return "BL"
    if (nearRight && nearBottom)
        return "BR"
    return ""
}

; 모서리를 누른 채 끄는 동안 반대쪽 모서리(anchor)를 고정점으로 삼아,
; anchor로부터의 거리 비율만큼 배율을 바꿔 종횡비를 유지하며 크기 조정.
ResizeFromCorner(corner, startMx, startMy) {
    global mapGui, pic, baseW, baseH, scale

    mapGui.GetPos(&wx, &wy, &ww, &wh)
    startScale := scale

    if (corner = "TL")
        anchorX := wx + ww, anchorY := wy + wh
    else if (corner = "TR")
        anchorX := wx, anchorY := wy + wh
    else if (corner = "BL")
        anchorX := wx + ww, anchorY := wy
    else ; "BR"
        anchorX := wx, anchorY := wy

    startDist := Sqrt((startMx - anchorX) ** 2 + (startMy - anchorY) ** 2)
    if (startDist < 1)
        startDist := 1

    finalW := ww
    finalH := wh
    while (GetKeyState("LButton", "P")) {
        MouseGetPos(&curMx, &curMy)
        curDist := Sqrt((curMx - anchorX) ** 2 + (curMy - anchorY) ** 2)
        newScale := startScale * (curDist / startDist)
        if (newScale < 0.1)
            newScale := 0.1
        if (newScale > 5.0)
            newScale := 5.0
        scale := newScale

        w := Round(baseW * scale)
        h := Round(baseH * scale)
        finalW := w, finalH := h

        if (corner = "TL")
            newWx := anchorX - w, newWy := anchorY - h
        else if (corner = "TR")
            newWx := anchorX, newWy := anchorY - h
        else if (corner = "BL")
            newWx := anchorX - w, newWy := anchorY
        else ; "BR"
            newWx := anchorX, newWy := anchorY

        ; 드래그 도중에는 빠른 미리보기로 컨트롤만 리사이즈(약간의 화질 열화는
        ; 있을 수 있음). 마우스를 놓는 순간 아래에서 정확한 크기로 다시 로드한다.
        pic.Move(0, 0, w, h)
        mapGui.Move(newWx, newWy, w, h)
        Sleep(10)
    }
    ReloadPicAtSize(finalW, finalH)
    ShowStatus("배율: " Round(scale * 100) "%")
}

; 마우스를 누른 채 이동하는 동안 실시간으로 창 위치를 따라오게 하는 방식.
; (이전 버전의 WM_NCLBUTTONDOWN 트릭보다 확실하게 동작함)
DragOverlay(startMx, startMy) {
    global mapGui
    mapGui.GetPos(&startWx, &startWy)
    while (GetKeyState("LButton", "P")) {
        MouseGetPos(&curMx, &curMy)
        mapGui.Move(startWx + (curMx - startMx), startWy + (curMy - startMy))
        Sleep(10)
    }
}

; =====================================================================
; 방향키로 미세 이동 (편집 모드에서만 동작, 클릭 통과 모드에서는 화살표 키가
; 평소처럼 Emme4로 그대로 전달됨)
; =====================================================================
~Up::    NudgeOverlay(0, -1)
~Down::  NudgeOverlay(0, 1)
~Left::  NudgeOverlay(-1, 0)
~Right:: NudgeOverlay(1, 0)
~+Up::    NudgeOverlay(0, -10)
~+Down::  NudgeOverlay(0, 10)
~+Left::  NudgeOverlay(-10, 0)
~+Right:: NudgeOverlay(10, 0)

NudgeOverlay(dx, dy) {
    global editMode, mapGui, overlayReady
    if (!overlayReady || !editMode)
        return
    mapGui.GetPos(&wx, &wy)
    mapGui.Move(wx + dx, wy + dy)
}

; =====================================================================
; 확대 / 축소 (Shift + 마우스 휠, 커서 위치를 기준으로 배율 변경, 편집 모드에서만)
; =====================================================================
~+WheelUp:: ZoomStep(1)
~+WheelDown:: ZoomStep(-1)

ZoomStep(direction) {
    global editMode, scale, mapGui, pic, baseW, baseH, overlayReady
    if (!overlayReady || !editMode)
        return

    MouseGetPos(&mx, &my)
    mapGui.GetPos(&wx, &wy)
    ; 커서 아래 지점이 화면상 같은 자리에 남도록, 배율 변경 전 기준(배율 1) 좌표를 구해둔다
    relX := (mx - wx) / scale
    relY := (my - wy) / scale

    newScale := scale + (0.05 * direction)
    if (newScale < 0.1)
        newScale := 0.1
    if (newScale > 5.0)
        newScale := 5.0
    scale := newScale

    w := Round(baseW * scale)
    h := Round(baseH * scale)
    newWx := Round(mx - relX * scale)
    newWy := Round(my - relY * scale)

    ReloadPicAtSize(w, h)
    mapGui.Move(newWx, newWy, w, h)
    ShowStatus("배율: " Round(scale * 100) "%")
}

; =====================================================================
; 투명도 조절
; =====================================================================
^!Up:: AdjustOpacity(15)
^!Down:: AdjustOpacity(-15)

AdjustOpacity(delta) {
    global editMode, opacity, mapGui, overlayReady
    if (!overlayReady || !editMode)
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
    global editMode, imgPath, mapGui, posX, posY, scale, opacity, calibState, overlayReady
    if (!overlayReady)
        return
    if (calibState != 0) {
        ShowStatus("정렬 진행 중에는 이미지를 변경할 수 없습니다 (Esc로 취소 후 다시 시도)")
        return
    }
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
    overlayReady := false
    mapGui.Destroy()
    CreateOverlay()
    overlayReady := true
    ApplyEditMode()
    ShowStatus("이미지 교체됨: " imgPath)
}

SelectImage() {
    return FileSelect(1, , "지도 이미지 선택", "이미지 (*.png; *.jpg; *.jpeg; *.bmp; *.gif)")
}

; =====================================================================
; 참조점 기반 반자동 정렬
; =====================================================================
^!r:: StartCalibration()
~Esc:: CancelCalibration()

StartCalibration(*) {
    global editMode, calibState, calibImgP1, calibImgP2, calibScreenP1, overlayReady
    if (!overlayReady)
        return

    editMode := true
    ApplyEditMode()
    calibImgP1 := "", calibImgP2 := "", calibScreenP1 := ""
    calibState := 1
    ShowStatus("정렬 1/4: 지도 이미지에서 기준점 1을 클릭하세요 (Esc: 취소)")
}

CancelCalibration(*) {
    global calibState
    if (calibState = 0)
        return
    calibState := 0
    ShowStatus("정렬 취소됨 (Ctrl+Alt+T로 원하는 모드로 전환하세요)")
}

ApplyCalibration() {
    global calibImgP1, calibImgP2, calibScreenP1, calibScreenP2
    global mapGui, pic, baseW, baseH, scale, posX, posY, editMode

    imgDx := calibImgP2[1] - calibImgP1[1]
    imgDy := calibImgP2[2] - calibImgP1[2]
    imgDist := Sqrt(imgDx ** 2 + imgDy ** 2)

    if (imgDist < 2) {
        ShowStatus("정렬 실패: 이미지 기준점 두 개가 너무 가깝습니다. Ctrl+Alt+R로 다시 시도하세요")
        return
    }

    scrDx := calibScreenP2[1] - calibScreenP1[1]
    scrDy := calibScreenP2[2] - calibScreenP1[2]
    scrDist := Sqrt(scrDx ** 2 + scrDy ** 2)

    newScale := scrDist / imgDist
    if (newScale < 0.05)
        newScale := 0.05
    if (newScale > 10.0)
        newScale := 10.0

    ; 기준점1(이미지) -> 기준점1(화면)이 정확히 겹치도록 이동량 역산
    tx := calibScreenP1[1] - newScale * calibImgP1[1]
    ty := calibScreenP1[2] - newScale * calibImgP1[2]

    scale := newScale
    posX := Round(tx)
    posY := Round(ty)

    w := Round(baseW * scale)
    h := Round(baseH * scale)
    ReloadPicAtSize(w, h)
    mapGui.Move(posX, posY, w, h)

    editMode := false
    ApplyClickThrough()
    ShowStatus("정렬 완료: 배율 " Round(scale * 100) "%, Emme4 조작 가능")
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
