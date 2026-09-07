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
;   좌클릭 드래그(가장자리) : 오버레이 모서리/변 근처(약 22px 이내, 상하좌우 어디든)를
;                        클릭한 채로 끌면 비율을 유지하며 크기 조정 (편집 모드,
;                        반대쪽 모서리/변이 고정된 채로 잡은 지점 방향으로 커지고 작아짐)
;   방향키            : 오버레이 1px 미세 이동 (편집 모드)
;   Shift+방향키       : 오버레이 10px 이동 (편집 모드)
;   Shift + 마우스휠  : 마우스 커서 위치를 기준으로 확대/축소 (편집 모드)
;   Ctrl+Alt+Up/Down  : 투명도 증가/감소 (편집 모드)
;   Ctrl+Alt+O        : 다른 지도 이미지로 교체 (편집 모드)
;   Ctrl+Alt+R        : 참조점 기반 반자동 정렬 시작 (아래 참고)
;   Ctrl+Alt+P        : 회전 기준점 지정 시작 (편집 모드로 자동 전환됨, 아래 참고)
;   Ctrl+Alt+[ / ]    : 기준점 중심으로 1도씩 반시계/시계 방향 회전 (편집 모드)
;   Ctrl+Alt+Shift+[ / ] : 기준점 중심으로 10도씩 회전 (편집 모드)
;   Ctrl+Alt+0        : 회전 초기화(0도로 복귀) (편집 모드)
;   Ctrl+Alt+L        : 오버레이 고정 <-> 고정 해제 (언제나 동작)
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
;
; 회전 (Ctrl+Alt+P로 기준점 지정 후 Ctrl+Alt+[ / ]):
;   1) 회전각이 0도인 상태에서 Ctrl+Alt+P -> 지도 이미지에서 회전축으로 삼을 지점 클릭
;   2) Ctrl+Alt+[ / ] (또는 Shift 병행으로 10도씩)로 그 지점을 중심으로 회전
;      회전 중에도 기준점은 화면상 같은 위치에 고정된 채로 지도만 돌아감
;   3) Ctrl+Alt+0으로 언제든 회전을 초기화(0도)할 수 있음(기준점을 다시 지정하려면
;      먼저 회전을 0도로 되돌려야 함)
;   * GDI+로 매번 이미지를 다시 렌더링하는 방식이라 이미지가 클 경우 다소 느릴 수 있음
;
; 고정 (Ctrl+Alt+L):
;   위치/배율/회전을 원하는 대로 맞춘 뒤 고정하면, 클릭 통과 모드로 강제 전환되고
;   실수로 편집 모드에 들어가거나 이동/크기조정/회전이 되는 일을 막아줍니다.
;   다시 Ctrl+Alt+L을 누르면 고정이 풀립니다.
; =====================================================================

CONFIG_FILE := A_ScriptDir "\MapOverlay.ini"
ROTATED_FILE := A_Temp "\MapOverlay_rotated.png"

; ---- 전역 상태 ----
mapGui         := ""
pic            := ""
sourceImgPath  := ""       ; 사용자가 선택한 회전 없는 원본 이미지(항상 이 파일에서 다시 렌더링)
imgPath        := ""       ; 현재 Picture 컨트롤에 실제로 로드된 파일(원본 또는 회전 렌더링 결과)
baseW          := 0        ; 현재 배율 1배 기준 표시 캔버스 크기(회전 반영됨)
baseH          := 0
origBaseW      := 0        ; 회전 계산의 기준이 되는, 회전 0도일 때의 원본 이미지 크기(고정)
origBaseH      := 0
scale          := 1.0
posX           := 100
posY           := 100
opacity        := 150      ; 0(완전 투명) ~ 255(불투명)
rotation       := 0.0      ; 현재 회전각(도, 시계방향 +)
editMode       := true     ; 시작 시에는 위치/배율을 맞출 수 있도록 편집 모드로 시작
overlayVisible := true
overlayReady   := false    ; CreateOverlay() 완료 전에는 모든 단축키가 무시됨(안전장치)
locked         := false    ; 고정 상태(위치/크기/회전 변경 금지)
EDGE_MARGIN    := 22       ; 모서리/변 크기조정으로 인식할 가장자리 폭(px)
gdipToken      := 0

; ---- 참조점 정렬(Calibration) 상태 ----
; 0=대기, 1=이미지 기준점1 대기, 2=이미지 기준점2 대기, 3=화면 기준점1 대기, 4=화면 기준점2 대기
calibState    := 0
calibImgP1    := ""
calibImgP2    := ""
calibScreenP1 := ""
calibScreenP2 := ""

; ---- 회전 기준점 지정 상태 ----
pivotState := 0    ; 0=대기, 1=지도 이미지에서 클릭 대기
pivotBaseX := ""   ; 회전 0도 기준 좌표계에서의 회전축 위치
pivotBaseY := ""

; ---- GDI+ 초기화 (회전 렌더링용, gdiplus.dll은 Windows에 기본 포함) ----
si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
NumPut("UInt", 1, si)
DllCall("gdiplus\GdiplusStartup", "UPtr*", &gdipToken, "Ptr", si, "Ptr", 0)

; =====================================================================
; 시작 절차
; =====================================================================
LoadSettings()

if (sourceImgPath = "" || !FileExist(sourceImgPath)) {
    sourceImgPath := SelectImage()
    if (sourceImgPath = "")
        ExitApp()
    rotation := 0.0
    pivotBaseX := "", pivotBaseY := ""
}

CreateOverlay()
overlayReady := true
OnExit(OnScriptExit)

ApplyEditMode()
ShowStatus("MapOverlay 시작 (Ctrl+Alt+T: 편집/클릭통과, Ctrl+Alt+H: 숨김/표시, Ctrl+Alt+L: 고정, Ctrl+Alt+Q: 종료)")

; =====================================================================
; 오버레이 창 생성
; =====================================================================
CreateOverlay() {
    global mapGui, pic, imgPath, sourceImgPath, baseW, baseH, origBaseW, origBaseH
    global scale, posX, posY, opacity, rotation

    mapGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "MapOverlay")
    mapGui.BackColor := "White"

    ; 항상 "회전 0도" 상태의 원본 이미지 크기를 먼저 알아내 회전 계산의 기준으로 삼는다.
    ; 화면 폭의 60%를 기준 폭으로 잡고, 이미지는 원본 비율을 유지하며 리사이즈됨
    ; (h를 생략하면 GUI 기본 높이로 늘어나 비율이 깨지므로, "-1"로 비율 유지 자동계산을 명시해야 함)
    defaultW := Round(A_ScreenWidth * 0.6)
    tmpPic := mapGui.Add("Picture", "x0 y0 w" defaultW " h-1 Hidden", sourceImgPath)
    tmpPic.GetPos(&px, &py, &pw, &ph)
    origBaseW := pw
    origBaseH := ph
    DllCall("DestroyWindow", "ptr", tmpPic.Hwnd)

    ; 현재 회전각에 맞는 표시 캔버스 크기 계산(0도면 원본 크기와 동일)
    if (Abs(rotation) < 0.001) {
        baseW := origBaseW
        baseH := origBaseH
    } else {
        ComputeRotatedCanvas(origBaseW, origBaseH, rotation, &cw, &ch)
        baseW := Round(cw)
        baseH := Round(ch)
    }

    if (scale <= 0)
        scale := 1.0

    w := Round(baseW * scale)
    h := Round(baseH * scale)
    if (w < 20 || h < 20) {
        w := baseW, h := baseH, scale := 1.0
    }

    RegenerateDisplayImage()   ; imgPath를 원본 또는 회전 렌더링 결과로 확정
    pic := mapGui.Add("Picture", "x0 y0 w" w " h" h, imgPath)

    mapGui.Show("x" posX " y" posY " w" w " h" h " NoActivate")
    WinSetTransparent(opacity, "ahk_id " mapGui.Hwnd)
}

; Picture 컨트롤을 Move()로 리사이즈하면 기존 비트맵을 다시 그리지 않고 가장자리를
; 늘려서 채우는 경우가 있어(확대 시 가장자리가 복제된 것처럼 보이는 현상), 배율이
; 바뀔 때마다 컨트롤을 새로 만들어 이미지를 해당 크기로 다시 로드/렌더링한다.
ReloadPicAtSize(w, h) {
    global mapGui, pic, imgPath
    ; GuiControl 객체에는 .Destroy() 메서드가 없으므로, 실제 자식 창을
    ; DestroyWindow API로 직접 제거한 뒤 같은 자리에 새로 추가한다.
    DllCall("DestroyWindow", "ptr", pic.Hwnd)
    pic := mapGui.Add("Picture", "x0 y0 w" w " h" h, imgPath)
}

; =====================================================================
; 회전 관련 좌표 계산
;
; 회전은 항상 "회전 0도일 때의 원본 이미지"(origBaseW x origBaseH, 고정값)를
; 기준으로 계산한다. 이렇게 하면 회전을 여러 번 반복해도 매번 원본에서 다시
; 렌더링하므로 화질이 누적으로 열화되지 않고, 기준점 좌표도 항상 같은
; 좌표계를 쓰면 되어 계산이 단순해진다.
; =====================================================================

; 원본 크기(w,h)를 angleDeg만큼 회전했을 때, 잘리지 않게 감싸는 사각형(캔버스) 크기
ComputeRotatedCanvas(w, h, angleDeg, &outW, &outH) {
    rad := angleDeg * 0.017453292519943295   ; * pi/180
    cosA := Abs(Cos(rad)), sinA := Abs(Sin(rad))
    outW := w * cosA + h * sinA
    outH := w * sinA + h * cosA
}

; 원본 좌표계의 점(px,py)이 angleDeg 회전 후 새 캔버스 좌표계에서 어디로 가는지 계산
MapPointRotated(px, py, w, h, angleDeg, &outX, &outY) {
    rad := angleDeg * 0.017453292519943295
    cosA := Cos(rad), sinA := Sin(rad)
    dx := px - w / 2
    dy := py - h / 2
    rx := dx * cosA - dy * sinA
    ry := dx * sinA + dy * cosA
    ComputeRotatedCanvas(w, h, angleDeg, &cw, &ch)
    outX := cw / 2 + rx
    outY := ch / 2 + ry
}

; GDI+로 srcPath 이미지를 (logicalW x logicalH) 크기에 맞춰 angleDeg만큼 회전시키고,
; 잘리지 않도록 확장된 캔버스에 그려 outPath(PNG)로 저장한다. 성공 시 true 반환.
; 참고: 이 함수는 Win32 GDI+ API를 직접 호출하는 방식이라, 이 코드를 작성한 환경에서는
; 실제 실행 검증을 하지 못했다. 문제가 있으면 오류 메시지를 알려주면 바로 고칠 수 있다.
RenderRotatedImage(srcPath, logicalW, logicalH, angleDeg, outPath) {
    PixelFormat32bppARGB := 0x26200A
    MatrixOrderPrepend := 0

    pSrc := 0, pCanvas := 0, pGraphics := 0
    ok := false

    try {
        if (DllCall("gdiplus\GdipLoadImageFromFile", "wstr", srcPath, "ptr*", &pSrc) != 0)
            throw Error("이미지 로드 실패")

        ComputeRotatedCanvas(logicalW, logicalH, angleDeg, &canvasWf, &canvasHf)
        canvasW := Max(1, Ceil(canvasWf))
        canvasH := Max(1, Ceil(canvasHf))

        if (DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", canvasW, "int", canvasH, "int", 0, "int", PixelFormat32bppARGB, "ptr", 0, "ptr*", &pCanvas) != 0)
            throw Error("캔버스 생성 실패")

        if (DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pCanvas, "ptr*", &pGraphics) != 0)
            throw Error("그래픽 컨텍스트 생성 실패")

        DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pGraphics, "int", 4)          ; AntiAlias
        DllCall("gdiplus\GdipSetInterpolationMode", "ptr", pGraphics, "int", 7)      ; HighQualityBicubic
        DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", pGraphics, "int", 2)        ; HighQuality

        ; 새 캔버스 중심으로 이동 -> 회전 -> 원본 이미지 중심이 원점에 오도록 이동
        DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", pGraphics, "float", canvasW / 2, "float", canvasH / 2, "int", MatrixOrderPrepend)
        DllCall("gdiplus\GdipRotateWorldTransform", "ptr", pGraphics, "float", angleDeg, "int", MatrixOrderPrepend)
        DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", pGraphics, "float", -logicalW / 2, "float", -logicalH / 2, "int", MatrixOrderPrepend)

        DllCall("gdiplus\GdipDrawImageRectI", "ptr", pGraphics, "ptr", pSrc, "int", 0, "int", 0, "int", Round(logicalW), "int", Round(logicalH))

        clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsid)   ; PNG 인코더(고정 CLSID)
        if (DllCall("gdiplus\GdipSaveImageToFile", "ptr", pCanvas, "wstr", outPath, "ptr", clsid, "ptr", 0) != 0)
            throw Error("파일 저장 실패")

        ok := true
    } catch {
        ok := false
    }

    if (pGraphics)
        DllCall("gdiplus\GdipDeleteGraphics", "ptr", pGraphics)
    if (pCanvas)
        DllCall("gdiplus\GdipDisposeImage", "ptr", pCanvas)
    if (pSrc)
        DllCall("gdiplus\GdipDisposeImage", "ptr", pSrc)

    return ok
}

; rotation 값에 따라 imgPath를 원본(sourceImgPath) 또는 회전 렌더링 결과로 확정한다.
RegenerateDisplayImage() {
    global rotation, sourceImgPath, imgPath, origBaseW, origBaseH, ROTATED_FILE

    if (Abs(rotation) < 0.001) {
        imgPath := sourceImgPath
        return
    }

    if (RenderRotatedImage(sourceImgPath, origBaseW, origBaseH, rotation, ROTATED_FILE))
        imgPath := ROTATED_FILE
    else {
        ShowStatus("회전 렌더링 실패 - 회전 없이 표시합니다")
        rotation := 0.0
        imgPath := sourceImgPath
    }
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
    global editMode, calibState, pivotState, overlayReady, locked
    if (!overlayReady)
        return
    if (locked) {
        ShowStatus("오버레이가 고정되어 있습니다 (Ctrl+Alt+L로 고정 해제)")
        return
    }
    if (calibState != 0 || pivotState != 0)
        CancelPendingAction()
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
    global mapGui, overlayVisible, calibState, pivotState, overlayReady
    if (!overlayReady)
        return
    if (calibState != 0 || pivotState != 0)
        CancelPendingAction()
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
; 고정 <-> 고정 해제
; =====================================================================
^!l:: ToggleLock()

ToggleLock(*) {
    global locked, editMode, calibState, pivotState, overlayReady
    if (!overlayReady)
        return
    if (calibState != 0 || pivotState != 0)
        CancelPendingAction()
    locked := !locked
    if (locked) {
        if (editMode) {
            editMode := false
            ApplyClickThrough()
        }
        ShowStatus("오버레이 고정됨 (위치/크기/회전 변경 불가) - Ctrl+Alt+L로 고정 해제")
    } else {
        ShowStatus("오버레이 고정 해제됨 - Ctrl+Alt+T로 편집 가능")
    }
}

; =====================================================================
; 좌클릭 처리: 드래그 이동 / 정렬·회전기준점 모드의 기준점 캡처
; =====================================================================
~LButton:: HandleLButton()

HandleLButton(*) {
    global editMode, calibState, calibImgP1, calibImgP2, calibScreenP1, calibScreenP2
    global pivotState, pivotBaseX, pivotBaseY, scale, mapGui, overlayReady
    if (!overlayReady)
        return

    MouseGetPos(&mx, &my)

    ; --- 회전 기준점 지정: 지도 이미지 위 클릭 ---
    if (pivotState = 1) {
        if (!IsOverOverlay(mx, my)) {
            ShowStatus("지도 이미지 위를 클릭해주세요")
            return
        }
        mapGui.GetPos(&wx, &wy)
        pivotBaseX := (mx - wx) / scale
        pivotBaseY := (my - wy) / scale
        pivotState := 0
        ShowStatus("회전 기준점 지정 완료 (Ctrl+Alt+[ / ] 로 회전)")
        return
    }

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

    zone := GetResizeZone(mx, my)
    if (zone != "")
        ResizeFromZone(zone, mx, my)
    else
        DragOverlay(mx, my)
}

; 클릭 좌표가 오버레이의 어느 모서리/변(가장자리 EDGE_MARGIN px 이내)에 있는지 판정.
; 모서리 4곳뿐 아니라 변(상/하/좌/우) 전체도 인식해서 크기조정 영역을 넓게 잡는다.
; 아무 곳도 아니면 빈 문자열을 반환(=몸통 클릭, 이동으로 처리).
GetResizeZone(mx, my) {
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
    if (nearTop)
        return "T"
    if (nearBottom)
        return "B"
    if (nearLeft)
        return "L"
    if (nearRight)
        return "R"
    return ""
}

; 모서리/변을 누른 채 끄는 동안 반대쪽(모서리는 반대쪽 모서리, 변은 반대쪽 변의
; 가운데)을 고정점(anchor)으로 삼아, anchor로부터의 거리 비율만큼 배율을 바꿔
; 종횡비를 유지하며 크기 조정한다. 항상 "지금 잡은 지점 -> 마우스 방향"으로
; 자연스럽게 커지거나 작아지도록, 창(부모)을 먼저 옮긴 뒤 이미지(자식)를 맞춘다.
ResizeFromZone(zone, startMx, startMy) {
    global mapGui, pic, baseW, baseH, scale

    mapGui.GetPos(&wx, &wy, &ww, &wh)
    startScale := scale

    ; anchor: 크기가 바뀌어도 고정되어야 하는 기준점
    ; hAlign/vAlign: 그 anchor가 새 사각형의 왼쪽/오른쪽/가운데, 위/아래/가운데 중
    ; 어디에 해당하는지(고정된 쪽이 그대로 유지되도록 새 위치를 계산하기 위함)
    if (zone = "TL")
        anchorX := wx + ww, anchorY := wy + wh, hAlign := "right", vAlign := "bottom"
    else if (zone = "TR")
        anchorX := wx, anchorY := wy + wh, hAlign := "left", vAlign := "bottom"
    else if (zone = "BL")
        anchorX := wx + ww, anchorY := wy, hAlign := "right", vAlign := "top"
    else if (zone = "BR")
        anchorX := wx, anchorY := wy, hAlign := "left", vAlign := "top"
    else if (zone = "T")
        anchorX := wx + ww / 2, anchorY := wy + wh, hAlign := "center", vAlign := "bottom"
    else if (zone = "B")
        anchorX := wx + ww / 2, anchorY := wy, hAlign := "center", vAlign := "top"
    else if (zone = "L")
        anchorX := wx + ww, anchorY := wy + wh / 2, hAlign := "right", vAlign := "center"
    else ; "R"
        anchorX := wx, anchorY := wy + wh / 2, hAlign := "left", vAlign := "center"

    startDist := Sqrt((startMx - anchorX) ** 2 + (startMy - anchorY) ** 2)
    if (startDist < 1)
        startDist := 1

    finalW := ww
    finalH := wh
    lastMx := startMx, lastMy := startMy
    while (GetKeyState("LButton", "P")) {
        MouseGetPos(&curMx, &curMy)
        if (curMx = lastMx && curMy = lastMy) {
            Sleep(10)
            continue
        }
        lastMx := curMx, lastMy := curMy

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

        newWx := (hAlign = "left") ? anchorX : (hAlign = "right") ? anchorX - w : anchorX - w / 2
        newWy := (vAlign = "top") ? anchorY : (vAlign = "bottom") ? anchorY - h : anchorY - h / 2
        newWx := Round(newWx), newWy := Round(newWy)

        ; 드래그 도중에는 빠른 미리보기: 창(부모)을 먼저 새 위치/크기로 옮긴 뒤
        ; 이미지(자식 컨트롤)를 맞춰서, 자식이 아직 안 움직인 부모 경계에 잘려
        ; 보이는 현상을 방지한다. 마우스를 놓는 순간 아래에서 정확한 크기로 다시 로드.
        mapGui.Move(newWx, newWy, w, h)
        pic.Move(0, 0, w, h)
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
    lastMx := startMx, lastMy := startMy
    while (GetKeyState("LButton", "P")) {
        MouseGetPos(&curMx, &curMy)
        if (curMx != lastMx || curMy != lastMy) {
            mapGui.Move(startWx + (curMx - startMx), startWy + (curMy - startMy))
            lastMx := curMx, lastMy := curMy
        }
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
    global editMode, sourceImgPath, rotation, pivotBaseX, pivotBaseY, mapGui
    global posX, posY, scale, opacity, calibState, pivotState, overlayReady
    if (!overlayReady)
        return
    if (calibState != 0 || pivotState != 0) {
        ShowStatus("정렬/회전 기준점 지정 중에는 이미지를 변경할 수 없습니다 (Esc로 취소 후 다시 시도)")
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
    sourceImgPath := newPath
    scale := 1.0
    rotation := 0.0
    pivotBaseX := "", pivotBaseY := ""
    overlayReady := false
    mapGui.Destroy()
    CreateOverlay()
    overlayReady := true
    ApplyEditMode()
    ShowStatus("이미지 교체됨: " sourceImgPath)
}

SelectImage() {
    return FileSelect(1, , "지도 이미지 선택", "이미지 (*.png; *.jpg; *.jpeg; *.bmp; *.gif)")
}

; =====================================================================
; 참조점 기반 반자동 정렬
; =====================================================================
^!r:: StartCalibration()
~Esc:: CancelPendingAction()

StartCalibration(*) {
    global editMode, calibState, calibImgP1, calibImgP2, calibScreenP1, overlayReady, locked
    if (!overlayReady)
        return
    if (locked) {
        ShowStatus("오버레이가 고정되어 있습니다 (Ctrl+Alt+L로 고정 해제)")
        return
    }

    editMode := true
    ApplyEditMode()
    calibImgP1 := "", calibImgP2 := "", calibScreenP1 := ""
    calibState := 1
    ShowStatus("정렬 1/4: 지도 이미지에서 기준점 1을 클릭하세요 (Esc: 취소)")
}

CancelPendingAction(*) {
    global calibState, pivotState
    if (calibState != 0) {
        calibState := 0
        ShowStatus("정렬 취소됨 (Ctrl+Alt+T로 원하는 모드로 전환하세요)")
    } else if (pivotState != 0) {
        pivotState := 0
        ShowStatus("회전 기준점 지정 취소됨")
    }
}

; =====================================================================
; 회전 (기준점 지정 + 회전)
; =====================================================================
^!p:: StartPivotPick()
^![:: RotateStep(-1)
^!]:: RotateStep(1)
^!+[:: RotateStep(-10)
^!+]:: RotateStep(10)
^!0:: ResetRotation()

StartPivotPick(*) {
    global editMode, calibState, pivotState, rotation, overlayReady, locked
    if (!overlayReady)
        return
    if (locked) {
        ShowStatus("오버레이가 고정되어 있습니다 (Ctrl+Alt+L로 고정 해제)")
        return
    }
    if (Abs(rotation) > 0.001) {
        ShowStatus("회전 기준점은 회전각이 0도일 때만 지정할 수 있습니다. Ctrl+Alt+0으로 초기화하세요")
        return
    }
    if (calibState != 0)
        CancelPendingAction()

    editMode := true
    ApplyEditMode()
    pivotState := 1
    ShowStatus("지도 이미지에서 회전 기준점으로 쓸 지점을 클릭하세요 (Esc: 취소)")
}

; 기준점(pivotBaseX/Y)이 화면상 같은 위치에 고정된 채로 rotation을 deltaDeg만큼 바꾼다.
RotateStep(deltaDeg) {
    global rotation, locked, editMode, overlayReady, pivotBaseX, pivotBaseY
    global mapGui, baseW, baseH, origBaseW, origBaseH, scale

    if (!overlayReady || locked)
        return
    if (!editMode) {
        ShowStatus("회전은 편집 모드에서만 가능합니다 (Ctrl+Alt+T)")
        return
    }
    if (pivotBaseX = "") {
        ShowStatus("먼저 Ctrl+Alt+P로 회전 기준점을 지정하세요")
        return
    }

    oldAngle := rotation
    newAngle := rotation + deltaDeg
    while (newAngle > 180)
        newAngle -= 360
    while (newAngle <= -180)
        newAngle += 360

    ; 회전 전, 기준점이 현재 화면의 어느 위치에 있는지 구해 그 자리에 고정시킨다
    mapGui.GetPos(&wx, &wy)
    MapPointRotated(pivotBaseX, pivotBaseY, origBaseW, origBaseH, oldAngle, &oldPX, &oldPY)
    screenPivotX := wx + oldPX * scale
    screenPivotY := wy + oldPY * scale

    rotation := newAngle
    RegenerateDisplayImage()

    ComputeRotatedCanvas(origBaseW, origBaseH, rotation, &cw, &ch)
    baseW := Round(cw)
    baseH := Round(ch)

    MapPointRotated(pivotBaseX, pivotBaseY, origBaseW, origBaseH, rotation, &newPX, &newPY)
    newWx := Round(screenPivotX - newPX * scale)
    newWy := Round(screenPivotY - newPY * scale)

    w := Round(baseW * scale)
    h := Round(baseH * scale)
    mapGui.Move(newWx, newWy, w, h)
    ReloadPicAtSize(w, h)

    ShowStatus("회전: " Round(rotation, 1) "도")
}

ResetRotation(*) {
    global rotation, locked, overlayReady
    if (!overlayReady || locked)
        return
    if (Abs(rotation) < 0.001) {
        ShowStatus("이미 회전각이 0도입니다")
        return
    }
    RotateStep(-rotation)
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
    global gdipToken
    SaveSettings()
    if (gdipToken)
        DllCall("gdiplus\GdiplusShutdown", "Ptr", gdipToken)
}

; 스크립트 폴더에 쓰기 권한이 없을 때(Program Files, 읽기전용/보호된 폴더 등) 대체할
; 항상 쓰기 가능한 사용자별 폴더
FallbackConfigFile() {
    dir := A_AppData "\MapOverlay"
    try DirCreate(dir)
    return dir "\MapOverlay.ini"
}

LoadSettings() {
    global sourceImgPath, scale, posX, posY, opacity, rotation, pivotBaseX, pivotBaseY, locked, CONFIG_FILE

    ; 이전 실행에서 스크립트 폴더에 쓰지 못해 대체 위치에 저장된 적이 있다면 그쪽을 사용
    if (!FileExist(CONFIG_FILE)) {
        altFile := FallbackConfigFile()
        if (FileExist(altFile))
            CONFIG_FILE := altFile
    }

    if !FileExist(CONFIG_FILE)
        return

    try {
        sourceImgPath := IniRead(CONFIG_FILE, "Overlay", "ImagePath", "")
        scale         := IniRead(CONFIG_FILE, "Overlay", "Scale", "1.0") + 0
        posX          := IniRead(CONFIG_FILE, "Overlay", "PosX", "100") + 0
        posY          := IniRead(CONFIG_FILE, "Overlay", "PosY", "100") + 0
        opacity       := IniRead(CONFIG_FILE, "Overlay", "Opacity", "150") + 0
        rotation      := IniRead(CONFIG_FILE, "Overlay", "Rotation", "0") + 0
        locked        := IniRead(CONFIG_FILE, "Overlay", "Locked", "0") + 0 ? true : false

        pivotXStr := IniRead(CONFIG_FILE, "Overlay", "PivotX", "")
        pivotYStr := IniRead(CONFIG_FILE, "Overlay", "PivotY", "")
        pivotBaseX := (pivotXStr = "") ? "" : pivotXStr + 0
        pivotBaseY := (pivotYStr = "") ? "" : pivotYStr + 0
    }
}

SaveSettings() {
    global sourceImgPath, scale, mapGui, opacity, rotation, pivotBaseX, pivotBaseY, locked
    global CONFIG_FILE, posX, posY

    if (mapGui != "")
        mapGui.GetPos(&posX, &posY)

    try {
        WriteAllSettings(CONFIG_FILE, posX, posY, sourceImgPath, scale, opacity, rotation, pivotBaseX, pivotBaseY, locked)
    } catch {
        ; 액세스 거부(오류 5) 등으로 실패하면 사용자 AppData 폴더로 대체 저장
        CONFIG_FILE := FallbackConfigFile()
        try WriteAllSettings(CONFIG_FILE, posX, posY, sourceImgPath, scale, opacity, rotation, pivotBaseX, pivotBaseY, locked)
    }
}

WriteAllSettings(file, x, y, imgPath, scale, opacity, rotation, pivotX, pivotY, locked) {
    IniWrite(x, file, "Overlay", "PosX")
    IniWrite(y, file, "Overlay", "PosY")
    IniWrite(imgPath, file, "Overlay", "ImagePath")
    IniWrite(scale, file, "Overlay", "Scale")
    IniWrite(opacity, file, "Overlay", "Opacity")
    IniWrite(rotation, file, "Overlay", "Rotation")
    IniWrite(pivotX = "" ? "" : pivotX, file, "Overlay", "PivotX")
    IniWrite(pivotY = "" ? "" : pivotY, file, "Overlay", "PivotY")
    IniWrite(locked ? 1 : 0, file, "Overlay", "Locked")
}

; =====================================================================
; 상태 표시 (화면 좌상단에 짧게 툴팁 표시)
; =====================================================================
ShowStatus(msg) {
    ToolTip(msg, 20, 20)
    SetTimer(() => ToolTip(), -1800)
}
