import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    minimumWidth: 880
    minimumHeight: 580
    title: "Secure Tiles"
    color: backend.qmlColors.bg

    property var c: backend.qmlColors
    property int motion: backend.animationsEnabled ? 115 : 0
    property real uiScale: backend.fontScale
    property bool compactMessages: backend.messageDensity === "Compact"
    property int corner: backend.cornerRadius
    property color buttonSurface: backend.buttonColor
    property color messageSurface: backend.chatBackground
    property bool favoritesOnly: false
    property color strongSurface: root.alphaColor(root.c.panel, Math.max(.84, backend.panelOpacity))
    property color softSurface: root.alphaColor(root.c.panel, Math.max(.68, backend.panelOpacity))
    function validColor(value) {
        return value !== undefined && value !== null && value.r !== undefined
               && value.g !== undefined && value.b !== undefined
    }
    function alphaColor(value, amount) {
        if (!validColor(value)) return Qt.rgba(0, 0, 0, 0)
        return Qt.rgba(value.r, value.g, value.b, amount)
    }
    function mixColor(a, b, amount) {
        if (!validColor(a)) a = Qt.rgba(.15, .16, .17, 1)
        if (!validColor(b)) b = a
        return Qt.rgba(a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount,
                       a.b + (b.b - a.b) * amount, a.a + (b.a - a.a) * amount)
    }

    Popup {
        id: imageViewer
        property url imageSource: ""
        property real zoom: 1
        property real fitZoom: 1
        function resetZoom() {
            if (viewerImage.implicitWidth <= 0 || viewerImage.implicitHeight <= 0) return
            fitZoom = Math.min(1, (imageViewport.width - 48) / viewerImage.implicitWidth,
                                  (imageViewport.height - 48) / viewerImage.implicitHeight)
            zoom = Math.max(0.1, fitZoom)
            imageViewport.contentX = 0; imageViewport.contentY = 0
        }
        function showImage(source) { imageSource = source; open(); Qt.callLater(resetZoom) }
        function changeZoom(factor) { zoom = Math.max(0.1, Math.min(8, zoom * factor)) }
        anchors.centerIn: Overlay.overlay
        width: Overlay.overlay ? Overlay.overlay.width : root.width
        height: Overlay.overlay ? Overlay.overlay.height : root.height
        padding: 0; modal: true; focus: true; closePolicy: Popup.CloseOnEscape
        onClosed: imageSource = ""
        background: Rectangle { color: "#e60a0b0d" }
        contentItem: Item {
            AppButton { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 18; text: "Close"; Layout.preferredWidth: 70; z: 3; onClicked: imageViewer.close() }
            Flickable {
                id: imageViewport
                anchors.fill: parent; anchors.topMargin: 58; anchors.bottomMargin: 64; anchors.leftMargin: 20; anchors.rightMargin: 20
                clip: true; boundsBehavior: Flickable.StopAtBounds
                contentWidth: Math.max(width, viewerImage.width); contentHeight: Math.max(height, viewerImage.height)
                Image {
                    id: viewerImage; source: imageViewer.imageSource; asynchronous: true; cache: false
                    width: Math.max(1, implicitWidth * imageViewer.zoom); height: Math.max(1, implicitHeight * imageViewer.zoom)
                    x: Math.max(0, (imageViewport.width - width) / 2); y: Math.max(0, (imageViewport.height - height) / 2)
                    fillMode: Image.PreserveAspectFit
                    onStatusChanged: if (status === Image.Ready) imageViewer.resetZoom()
                }
                MouseArea {
                    anchors.fill: parent; acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) { imageViewer.changeZoom(wheel.angleDelta.y > 0 ? 1.15 : 1 / 1.15); wheel.accepted = true }
                }
            }
            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 16; spacing: 7
                AppButton { text: "Zoom out"; Layout.preferredWidth: 86; onClicked: imageViewer.changeZoom(1 / 1.25) }
                AppText { text: Math.round(imageViewer.zoom * 100) + "%"; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 56; font.bold: true }
                AppButton { text: "Zoom in"; Layout.preferredWidth: 78; onClicked: imageViewer.changeZoom(1.25) }
                AppButton { text: "Fit"; quiet: true; Layout.preferredWidth: 54; onClicked: imageViewer.resetZoom() }
            }
        }
    }

    component Panel: Rectangle {
        color: root.alphaColor(root.c.panel, backend.panelOpacity)
        radius: root.corner
        border.width: color.a > 0 ? 1 : 0
        border.color: root.alphaColor(root.c.text, 0.1)
    }

    component AppText: Text {
        color: root.c.text
        font.family: "Segoe UI"
        font.pixelSize: Math.round(15 * root.uiScale)
        font.hintingPreference: Font.PreferFullHinting
        renderType: Text.NativeRendering
    }

    component AppButton: Button {
        id: control
        property bool accent: false
        property bool danger: false
        property bool quiet: false
        property bool selected: false
        property color textColor: root.c.text
        implicitHeight: 38
        implicitWidth: Math.max(70, contentItem.implicitWidth + 28)
        hoverEnabled: true
        font.family: "Segoe UI"
        font.pixelSize: Math.round(13 * root.uiScale)
        font.hintingPreference: Font.PreferFullHinting
        scale: down ? .98 : 1
        Behavior on scale { NumberAnimation { duration: root.motion; easing.type: Easing.OutCubic } }
        contentItem: Text {
            text: control.text
            color: control.textColor
            font: control.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
        }
        background: Rectangle {
            id: buttonBackground
            readonly property bool quietIdle: control.quiet && !control.hovered && !control.down && !control.selected
            readonly property real surfaceOpacity: backend.controlOpacity * (control.accent || control.danger || control.selected ? .82 : control.quiet ? (control.hovered || control.down ? .5 : .12) : control.hovered ? .92 : .76)
            readonly property color neutralTint: root.mixColor(root.c.tile, root.buttonSurface, control.hovered || control.down ? .36 : .28)
            readonly property color stateTint: root.mixColor(root.c.tile, root.c.accent, control.down ? .38 : control.hovered ? .3 : .23)
            readonly property color baseColor: control.danger ? root.mixColor(root.c.tile, root.c.danger, control.hovered || control.down ? .5 : .38) : control.accent || control.selected ? stateTint : control.hovered || control.down ? Qt.lighter(neutralTint, 1.1) : neutralTint
            radius: Math.max(4, root.corner - 2)
            border.width: quietIdle ? 0 : 1
            border.color: control.danger ? root.alphaColor(root.c.danger, .9) : control.accent || control.selected ? root.alphaColor(root.c.accent, .78) : root.alphaColor(root.mixColor(root.c.text, root.buttonSurface, .55), .34)
            color: root.alphaColor(baseColor, surfaceOpacity)
            gradient: Gradient {
                GradientStop { position: 0; color: root.alphaColor(Qt.lighter(buttonBackground.baseColor, 1.04), buttonBackground.surfaceOpacity) }
                GradientStop { position: 1; color: root.alphaColor(buttonBackground.baseColor, buttonBackground.surfaceOpacity) }
            }
            Behavior on color { ColorAnimation { duration: root.motion } }
        }
    }

    component AppField: TextField {
        id: field
        implicitHeight: 38
        color: root.c.text
        placeholderTextColor: root.c.muted
        selectionColor: root.c.accent
        selectedTextColor: root.c.bg
        font.family: "Segoe UI"
        font.pixelSize: Math.round(15 * root.uiScale)
        font.hintingPreference: Font.PreferFullHinting
        leftPadding: 13; rightPadding: 13
        background: Rectangle {
            color: root.alphaColor(root.mixColor(root.c.bg, root.buttonSurface, .18), Math.max(.9, backend.controlOpacity)); radius: Math.max(4, root.corner - 2); border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? root.c.accent : root.alphaColor(root.mixColor(root.c.text, root.buttonSurface, .62), .55)
        }
    }

    component AppMenuItem: MenuItem {
        id: menuItem
        implicitWidth: 210; implicitHeight: 38
        leftPadding: 12; rightPadding: 12
        font.family: "Segoe UI"; font.pixelSize: Math.round(13 * root.uiScale)
        contentItem: Text { text: menuItem.text; color: menuItem.enabled ? root.c.text : root.alphaColor(root.c.muted, .48); font: menuItem.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; renderType: Text.NativeRendering }
        background: Rectangle { radius: 7; color: menuItem.highlighted ? root.alphaColor(root.c.accent, .3) : menuItem.hovered ? root.alphaColor(root.c.hover, .82) : "transparent"; border.color: menuItem.highlighted ? root.alphaColor(root.c.accent, .58) : "transparent"; Behavior on color { ColorAnimation { duration: root.motion } } }
    }

    component AppMenuSeparator: MenuSeparator {
        implicitHeight: 9
        contentItem: Rectangle { anchors.verticalCenter: parent.verticalCenter; height: 1; color: root.alphaColor(root.c.text, .13) }
    }

    component AppMenu: Menu {
        implicitWidth: 222; padding: 6
        margins: 8
        background: Rectangle { radius: 10; color: root.alphaColor(root.c.panel, .98); border.width: 1; border.color: root.alphaColor(root.c.text, .18) }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.motion } NumberAnimation { property: "scale"; from: .97; to: 1; duration: root.motion; easing.type: Easing.OutCubic } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 80 } }
    }

    component AppComboBox: ComboBox {
        id: combo
        implicitHeight: 38; implicitWidth: 150
        leftPadding: 12; rightPadding: 36
        font.family: "Segoe UI"; font.pixelSize: Math.round(13 * root.uiScale)
        contentItem: Text { text: combo.displayText; color: combo.enabled ? root.c.text : root.c.muted; font: combo.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; renderType: Text.NativeRendering }
        indicator: Text { x: combo.width - width - 12; anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: combo.popup.visible ? root.c.accent : root.c.muted; font.pixelSize: 17 }
        background: Rectangle { radius: Math.max(4, root.corner - 2); color: root.alphaColor(root.mixColor(root.c.tile, root.buttonSurface, .3), backend.controlOpacity * .8); border.width: 1; border.color: combo.activeFocus || combo.popup.visible ? root.c.accent : root.alphaColor(root.c.text, .22) }
        delegate: ItemDelegate { required property int index; width: combo.width; height: 38; text: combo.textAt(index); highlighted: combo.highlightedIndex === index
            contentItem: Text { text: parent.text; color: parent.highlighted ? root.c.text : root.c.muted; font: combo.font; verticalAlignment: Text.AlignVCenter; leftPadding: 6; elide: Text.ElideRight; renderType: Text.NativeRendering }
            background: Rectangle { radius: 7; color: parent.highlighted ? root.alphaColor(root.c.accent, .3) : parent.hovered ? root.alphaColor(root.c.hover, .82) : "transparent" }
        }
        popup: Popup { y: combo.height + 4; width: combo.width; implicitHeight: Math.min(contentItem.implicitHeight + 12, 260); padding: 6
            contentItem: ListView { clip: true; implicitHeight: contentHeight; model: combo.popup.visible ? combo.delegateModel : null; currentIndex: combo.highlightedIndex; ScrollIndicator.vertical: ScrollIndicator { } }
            background: Rectangle { radius: 10; color: root.alphaColor(root.c.panel, .98); border.width: 1; border.color: root.alphaColor(root.c.text, .18) }
        }
    }

    component StatusBadge: Rectangle {
        id: badge
        property string status: "Offline"
        property int size: 14
        width: size; height: size; radius: size / 2; z: 5
        color: status === "Online" ? "#23a55a" : status === "Away" ? "#f0b232" : status === "Do Not Disturb" ? "#f23f43" : "#80848e"
        border.width: 2; border.color: root.c.panel
        AppText {
            anchors.centerIn: parent
            text: badge.status === "Do Not Disturb" ? "−" : badge.status === "Away" ? "◔" : ""
            color: badge.status === "Away" ? root.c.bg : "white"
            font.pixelSize: Math.max(7, badge.size * .62); font.bold: true
        }
    }

    component Avatar: Item {
        id: avatar
        property int size: 40
        property string initials: backend.displayName.slice(0, 2).toUpperCase()
        property string status: backend.presence
        property url source: backend.avatarUrl
        width: size; height: size
        Rectangle {
            anchors.fill: parent; radius: avatar.size / 2; color: root.c.accent
            Rectangle { id: avatarMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
            Image {
                anchors.fill: parent; source: avatar.source; fillMode: Image.PreserveAspectCrop; visible: avatar.source.toString() !== ""; cache: false
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: avatarMask }
            }
            Text { anchors.centerIn: parent; visible: avatar.source.toString() === ""; text: avatar.initials; color: root.c.bg; font.bold: true; font.pixelSize: avatar.size * .34; renderType: Text.NativeRendering }
        }
        StatusBadge { status: avatar.status; size: Math.max(12, Math.round(avatar.size * .32)); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: -1; anchors.bottomMargin: -1 }
    }

    Rectangle {
        id: titleBar
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 36; color: "#090a0c"; z: 100
        RowLayout {
            anchors.fill: parent; spacing: 0
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                RowLayout { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: 12; spacing: 8
                    AppText { text: "◆"; color: root.c.accent; font.pixelSize: 8 }
                    AppText { text: "SECURE TILES"; font.pixelSize: 10; font.bold: true }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.startSystemMove()
                    onDoubleClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
                }
            }
            Rectangle {
                Layout.preferredWidth: 46; Layout.fillHeight: true; color: minimizeArea.containsMouse ? root.c.hover : "transparent"
                AppText { anchors.centerIn: parent; text: "—"; font.pixelSize: 13 }
                MouseArea { id: minimizeArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.showMinimized() }
            }
            Rectangle {
                Layout.preferredWidth: 46; Layout.fillHeight: true; color: maximizeArea.containsMouse ? root.c.hover : "transparent"
                AppText { anchors.centerIn: parent; text: root.visibility === Window.Maximized ? "❐" : "□"; font.pixelSize: 13 }
                MouseArea { id: maximizeArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized() }
            }
            Rectangle {
                Layout.preferredWidth: 46; Layout.fillHeight: true; color: closeArea.containsMouse ? "#c42b1c" : "transparent"
                AppText { anchors.centerIn: parent; text: "×"; font.pixelSize: 18 }
                MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.close() }
            }
        }
    }

    StackView {
        id: mainStack
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: titleBar.bottom; anchors.bottom: parent.bottom
        initialItem: backend.page === "auth" ? authPage : messengerPage
        replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.motion } }
        replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: root.motion } }
    }

    // Thin hit targets call Qt's native system-resize path. Windows controls
    // the resize loop, preserving smooth rendering on high-refresh displays.
    MouseArea { z: 200; enabled: root.visibility !== Window.Maximized; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 6; cursorShape: Qt.SizeHorCursor; onPressed: root.startSystemResize(Qt.LeftEdge) }
    MouseArea { z: 200; enabled: root.visibility !== Window.Maximized; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 6; cursorShape: Qt.SizeHorCursor; onPressed: root.startSystemResize(Qt.RightEdge) }
    MouseArea { z: 200; enabled: root.visibility !== Window.Maximized; anchors { left: parent.left; right: parent.right; top: parent.top } height: 6; cursorShape: Qt.SizeVerCursor; onPressed: root.startSystemResize(Qt.TopEdge) }
    MouseArea { z: 200; enabled: root.visibility !== Window.Maximized; anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 6; cursorShape: Qt.SizeVerCursor; onPressed: root.startSystemResize(Qt.BottomEdge) }
    MouseArea { z: 201; enabled: root.visibility !== Window.Maximized; anchors { left: parent.left; top: parent.top } width: 10; height: 10; cursorShape: Qt.SizeFDiagCursor; onPressed: root.startSystemResize(Qt.LeftEdge | Qt.TopEdge) }
    MouseArea { z: 201; enabled: root.visibility !== Window.Maximized; anchors { right: parent.right; top: parent.top } width: 10; height: 10; cursorShape: Qt.SizeBDiagCursor; onPressed: root.startSystemResize(Qt.RightEdge | Qt.TopEdge) }
    MouseArea { z: 201; enabled: root.visibility !== Window.Maximized; anchors { left: parent.left; bottom: parent.bottom } width: 10; height: 10; cursorShape: Qt.SizeBDiagCursor; onPressed: root.startSystemResize(Qt.LeftEdge | Qt.BottomEdge) }
    MouseArea { z: 201; enabled: root.visibility !== Window.Maximized; anchors { right: parent.right; bottom: parent.bottom } width: 10; height: 10; cursorShape: Qt.SizeFDiagCursor; onPressed: root.startSystemResize(Qt.RightEdge | Qt.BottomEdge) }

    Connections {
        target: backend
        function onChanged() {
            var wanted = backend.page === "auth" ? authPage : messengerPage
            var wantedName = backend.page === "auth" ? "auth" : "messenger"
            if (!mainStack.currentItem || mainStack.currentItem.objectName !== wantedName)
                mainStack.replace(wanted)
        }
    }

    Component {
        id: authPage
        Item {
            objectName: "auth"
            Rectangle { anchors.fill: parent; color: root.c.bg }
            AnimatedImage { anchors.fill: parent; source: backend.wallpaperUrl; fillMode: Image.PreserveAspectCrop; opacity: backend.wallpaperOpacity; visible: source !== "" }
            Panel {
                width: Math.min(440, parent.width - 48)
                height: backend.hasVault ? 410 : 470
                anchors.centerIn: parent
                radius: 18
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 38; spacing: 10
                    AppText { text: "SECURE TILES"; font.pixelSize: 25; font.bold: true }
                    AppText { text: "Private conversations. Keys stay yours."; color: root.c.muted }
                    Item { Layout.preferredHeight: 10 }
                    AppText { text: backend.hasVault ? "Welcome back, " + backend.vaultName : "Create your account"; font.pixelSize: 18; font.bold: true }
                    AppText { visible: !backend.hasVault; text: "USERNAME"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                    AppField { id: signupName; visible: !backend.hasVault; Layout.fillWidth: true; placeholderText: "e.g. alex_92" }
                    AppText { text: "VAULT PASSPHRASE"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                    AppField {
                        id: password; Layout.fillWidth: true; echoMode: TextInput.Password
                        placeholderText: backend.hasVault ? "Enter your passphrase" : "At least 10 characters"
                        onAccepted: backend.hasVault ? backend.unlock(text, "") : backend.signup(signupName.text, text)
                    }
                    AppText { visible: !backend.hasVault; text: "Securely connects through the hosted relay automatically."; color: root.c.muted; font.pixelSize: 11 }
                    AppText { Layout.fillWidth: true; text: backend.status; color: backend.busy ? root.c.accent : root.c.danger; wrapMode: Text.Wrap; font.pixelSize: 12 }
                    Item { Layout.fillHeight: true }
                    AppButton {
                        Layout.fillWidth: true; accent: true; enabled: !backend.busy
                        text: backend.busy ? (backend.hasVault ? "Connecting..." : "Creating account...") : backend.hasVault ? "Unlock" : "Create secure account"
                        onClicked: backend.hasVault ? backend.unlock(password.text, "") : backend.signup(signupName.text, password.text)
                    }
                }
            }
        }
    }

    Component {
        id: messengerPage
        Item {
            objectName: "messenger"
            Shortcut { sequence: "Ctrl+,"; onActivated: backend.openSettingsTab("My Profile") }
            Shortcut { sequence: "Ctrl+K"; onActivated: { if (backend.sidebarExpanded) contactSearch.forceActiveFocus() } }
            Shortcut { sequence: "Escape"; onActivated: { profilePopup.close(); presencePopup.close(); if (backend.page !== "chat") backend.openPage("chat") } }
            Rectangle { anchors.fill: parent; color: root.c.bg }
            AnimatedImage { anchors.fill: parent; source: backend.wallpaperUrl; fillMode: Image.PreserveAspectCrop; opacity: backend.wallpaperOpacity; visible: source !== "" }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 14; spacing: 10
                Panel {
                    Layout.fillWidth: true; Layout.preferredHeight: 48; color: root.strongSurface
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 14; spacing: 9
                        Rectangle { width: 9; height: 9; radius: 3; rotation: 45; color: root.c.accent }
                        AppText { text: "SECURE TILES"; font.pixelSize: 16; font.bold: true; font.letterSpacing: .4 }
                        Rectangle { width: 1; height: 18; color: root.alphaColor(root.c.text, .16) }
                        AppText { text: backend.displayName; color: root.c.muted; font.family: backend.displayFont; font.pixelSize: 12; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Rectangle { width: 8; height: 8; radius: 4; color: backend.relayStatus === "Relay connected" ? "#22c55e" : root.c.danger }
                        AppText { text: backend.relayStatus; color: root.c.muted; font.pixelSize: 12; font.bold: true }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                    Panel {
                        Layout.preferredWidth: 64; Layout.fillHeight: true; color: root.strongSurface
                        ColumnLayout { anchors.fill: parent; anchors.margins: 7; spacing: 8
                            ListView { id: serverRailList; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7; clip: true; model: backend.serverRailItems
                                delegate: Item {
                                    id: railItem; required property var modelData; width: 50; height: modelData.type === "folder" ? (modelData.expanded ? 58 + modelData.servers.length * 46 : 50) : 50; implicitHeight: height
                                    Loader { width: railItem.width; height: railItem.height; sourceComponent: modelData.type === "folder" ? railFolder : railServer }
                                    Component { id: railServer
                                        Item { id: serverNode; property string serverId: railItem.modelData.id; property real dragOriginX: 0; property real dragOriginY: 0; x: 0; width: 50; height: 50; z: serverDrag.drag.active ? 20 : 1; scale: serverFolderTarget.containsDrag ? 1.1 : 1
                                            Drag.active: serverDrag.drag.active; Drag.source: serverNode; Drag.hotSpot.x: 25; Drag.hotSpot.y: 25
                                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                            Rectangle { anchors.fill: parent; radius: 25; clip: true; color: serverFolderTarget.containsDrag ? root.c.hover : root.c.tile; border.color: serverFolderTarget.containsDrag || backend.selectedServerId === serverNode.serverId ? root.c.accent : "transparent"; border.width: serverFolderTarget.containsDrag ? 3 : 2
                                                Rectangle { id: standaloneIconMask; anchors.fill: parent; anchors.margins: 2; radius: width / 2; visible: false; layer.enabled: true }
                                                AnimatedImage { anchors.fill: parent; anchors.margins: 2; source: railItem.modelData.icon || ""; fillMode: Image.PreserveAspectCrop; visible: source !== ""; layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: standaloneIconMask } }
                                                AppText { anchors.centerIn: parent; visible: !(railItem.modelData.icon || ""); text: railItem.modelData.name.slice(0,2).toUpperCase(); font.bold: true }
                                            }
                                            MouseArea { id: serverDrag; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; drag.target: serverNode
                                                onPressed: { serverNode.dragOriginX = serverNode.x; serverNode.dragOriginY = serverNode.y }
                                                onClicked: function(mouse) { if (mouse.button === Qt.RightButton) serverIconMenu.popup(); else backend.selectServer(serverNode.serverId) }
                                                onReleased: { serverNode.Drag.drop(); serverNode.x = serverNode.dragOriginX; serverNode.y = serverNode.dragOriginY }
                                            }
                                            ToolTip.visible: serverDrag.containsMouse && !serverDrag.drag.active; ToolTip.text: railItem.modelData.name
                                            DropArea { id: serverFolderTarget; anchors.fill: parent; anchors.topMargin: 12; anchors.bottomMargin: 12; onDropped: function(drop) { if (drop.source && drop.source.serverId) backend.moveServer(drop.source.serverId, serverNode.serverId); drop.acceptProposedAction() } }
                                            DropArea { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 12; z: 4; onDropped: function(drop) { if (drop.source && drop.source.serverId) backend.reorderServer(drop.source.serverId, serverNode.serverId, true); drop.acceptProposedAction() } }
                                            DropArea { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 12; z: 4; onDropped: function(drop) { if (drop.source && drop.source.serverId) backend.reorderServer(drop.source.serverId, serverNode.serverId, false); drop.acceptProposedAction() } }
                                            AppMenu { id: serverIconMenu
                                                AppMenuItem { text: "Change server icon"; onTriggered: backend.chooseServerIconFor(serverNode.serverId) }
                                                AppMenuItem { text: "Remove custom icon"; enabled: (railItem.modelData.icon || "") !== ""; onTriggered: backend.removeServerIcon(serverNode.serverId) }
                                                AppMenuSeparator { }
                                                AppMenuItem { text: "Open server settings"; onTriggered: { backend.selectServer(serverNode.serverId); serverSettings.open() } }
                                            }
                                        }
                                    }
                                    Component { id: railFolder
                                        Rectangle { id: folderBox; property color folderTint: railItem.modelData.color || root.c.accent; width: railItem.width; height: railItem.height; radius: 18; color: root.alphaColor(folderTint, .2); border.color: root.alphaColor(folderTint, .72); border.width: 1
                                            Rectangle { id: folderButton; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; anchors.topMargin: 4; width: 42; height: 42; radius: 15; color: folderBox.folderTint
                                                Rectangle { id: customFolderMask; anchors.fill: parent; anchors.margins: 2; radius: 13; visible: false; layer.enabled: true }
                                                AnimatedImage { anchors.fill: parent; anchors.margins: 2; source: railItem.modelData.icon || ""; fillMode: Image.PreserveAspectCrop; visible: source !== ""; layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: customFolderMask } }
                                                AppText { anchors.centerIn: parent; visible: !(railItem.modelData.icon || ""); text: railItem.modelData.expanded ? "−" : "▰"; font.pixelSize: 18; font.bold: true }
                                                MouseArea { id: folderButtonArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                    onClicked: function(mouse) { if (mouse.button === Qt.RightButton) folderMenu.popup(); else backend.toggleServerFolder(railItem.modelData.id) }
                                                }
                                                ToolTip.visible: folderButtonArea.containsMouse; ToolTip.text: (railItem.modelData.expanded ? "Close " : "Open ") + railItem.modelData.name
                                            }
                                            Column { visible: railItem.modelData.expanded; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; anchors.topMargin: 52; spacing: 4
                                                Repeater { model: railItem.modelData.servers
                                                    Item { id: folderServer; required property var modelData; property string serverId: modelData.id; property real dragOriginX: 0; property real dragOriginY: 0; width: 42; height: 42; z: folderDrag.drag.active ? 20 : 1; scale: existingFolderTarget.containsDrag ? 1.1 : 1
                                                        Drag.active: folderDrag.drag.active; Drag.source: folderServer; Drag.hotSpot.x: 21; Drag.hotSpot.y: 21
                                                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                        Rectangle { anchors.fill: parent; radius: 21; clip: true; color: existingFolderTarget.containsDrag ? root.c.hover : root.c.tile; border.color: existingFolderTarget.containsDrag || backend.selectedServerId === folderServer.serverId ? root.c.accent : "transparent"; border.width: existingFolderTarget.containsDrag ? 3 : 2
                                                            Rectangle { id: folderIconMask; anchors.fill: parent; anchors.margins: 2; radius: width / 2; visible: false; layer.enabled: true }
                                                            AnimatedImage { anchors.fill: parent; anchors.margins: 2; source: modelData.icon || ""; fillMode: Image.PreserveAspectCrop; visible: source !== ""; layer.enabled: true; layer.effect: MultiEffect { maskEnabled: true; maskSource: folderIconMask } }
                                                            AppText { anchors.centerIn: parent; visible: !(modelData.icon || ""); text: modelData.name.slice(0,2).toUpperCase(); font.bold: true }
                                                        }
                                                        MouseArea { id: folderDrag; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; drag.target: folderServer
                                                            onPressed: { folderServer.dragOriginX = folderServer.x; folderServer.dragOriginY = folderServer.y }
                                                            onClicked: function(mouse) { if (mouse.button === Qt.RightButton) folderServerMenu.popup(); else backend.selectServer(folderServer.serverId) }
                                                            onReleased: { folderServer.Drag.drop(); folderServer.x = folderServer.dragOriginX; folderServer.y = folderServer.dragOriginY }
                                                        }
                                                        ToolTip.visible: folderDrag.containsMouse && !folderDrag.drag.active; ToolTip.text: modelData.name
                                                        DropArea { id: existingFolderTarget; anchors.fill: parent; anchors.topMargin: 10; anchors.bottomMargin: 10; onDropped: function(drop) { if (drop.source && drop.source.serverId) backend.moveServer(drop.source.serverId, railItem.modelData.id); drop.acceptProposedAction() } }
                                                        DropArea { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 10; z: 4; onDropped: function(drop) { if (drop.source && drop.source.serverId) backend.reorderServer(drop.source.serverId, folderServer.serverId, true); drop.acceptProposedAction() } }
                                                        DropArea { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 10; z: 4; onDropped: function(drop) { if (drop.source && drop.source.serverId) backend.reorderServer(drop.source.serverId, folderServer.serverId, false); drop.acceptProposedAction() } }
                                                        AppMenu { id: folderServerMenu
                                                            AppMenuItem { text: "Change server icon"; onTriggered: backend.chooseServerIconFor(folderServer.serverId) }
                                                            AppMenuItem { text: "Remove custom icon"; enabled: (modelData.icon || "") !== ""; onTriggered: backend.removeServerIcon(folderServer.serverId) }
                                                            AppMenuSeparator { }
                                                            AppMenuItem { text: "Open server settings"; onTriggered: { backend.selectServer(folderServer.serverId); serverSettings.open() } }
                                                        }
                                                    }
                                                }
                                            }
                                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: folderMenu.popup(); z: -1 }
                                        }
                                    }
                                    AppMenu { id: folderMenu
                                        AppMenuItem { text: "Change folder icon"; onTriggered: backend.chooseServerFolderIcon(modelData.id) }
                                        AppMenuItem { text: "Remove folder icon"; enabled: (modelData.icon || "") !== ""; onTriggered: backend.removeServerFolderIcon(modelData.id) }
                                        AppMenuSeparator { }
                                        AppMenuItem { text: "Customize folder: Violet"; onTriggered: backend.customizeServerFolder(modelData.id, modelData.name, "#7c3aed") }
                                        AppMenuItem { text: "Customize folder: Blue"; onTriggered: backend.customizeServerFolder(modelData.id, modelData.name, "#2563eb") }
                                        AppMenuItem { text: "Customize folder: Green"; onTriggered: backend.customizeServerFolder(modelData.id, modelData.name, "#16a34a") }
                                        AppMenuItem { text: "Customize folder: Rose"; onTriggered: backend.customizeServerFolder(modelData.id, modelData.name, "#e11d48") }
                                    }
                                }
                                footer: DropArea { width: serverRailList.width; height: Math.max(28, serverRailList.height - y)
                                    Rectangle { anchors.fill: parent; radius: 8; color: parent.containsDrag ? root.alphaColor(root.c.accent, .18) : "transparent"; border.color: parent.containsDrag ? root.alphaColor(root.c.accent, .72) : "transparent" }
                                    onDropped: function(drop) { if (drop.source && drop.source.serverId) backend.moveServerOutOfFolder(drop.source.serverId); drop.acceptProposedAction() }
                                }
                            }
                            AppButton { text: "+"; Layout.preferredWidth: 50; Layout.preferredHeight: 42; onClicked: serverCreatePopup.open(); ToolTip.visible: hovered; ToolTip.text: "Create or join a server" }
                        }
                    }
                    Popup { id: serverCreatePopup; parent: Overlay.overlay; anchors.centerIn: parent; width: 420; modal: true; focus: true; padding: 20
                        background: Rectangle { color: root.c.panel; radius: root.corner; border.color: root.alphaColor(root.c.text, .16) }
                        ColumnLayout { width: parent.width; spacing: 10
                            AppText { text: "Create or join a server"; font.pixelSize: 20; font.bold: true }
                            SectionLabel { text: "CREATE" }
                            AppField { id: createServerName; Layout.fillWidth: true; placeholderText: "Server name" }
                            AppButton { text: "Create server"; accent: true; enabled: createServerName.text.trim() !== ""; onClicked: { backend.createServer(createServerName.text); createServerName.text = ""; serverCreatePopup.close() } }
                            SectionLabel { text: "JOIN WITH AN INVITE" }
                            AppField { id: createJoinServerId; Layout.fillWidth: true; placeholderText: "Server ID" }
                            AppField { id: createJoinCode; Layout.fillWidth: true; placeholderText: "Invite code" }
                            AppButton { text: "Join server"; onClicked: { backend.joinServer(createJoinServerId.text, createJoinCode.text); serverCreatePopup.close() } }
                            SectionLabel { visible: backend.receivedServerInvites.length > 0; text: "INVITES FROM CONTACTS" }
                            Repeater { model: backend.receivedServerInvites
                                RowLayout { required property var modelData; Layout.fillWidth: true
                                    ColumnLayout { Layout.fillWidth: true; spacing: 1; AppText { text: modelData.server_name; font.bold: true } AppText { text: "From @" + modelData.from; color: root.c.muted; font.pixelSize: 11 } }
                                    AppButton { text: "Join"; onClicked: { backend.acceptServerInvite(modelData.server_id, modelData.code); serverCreatePopup.close() } }
                                }
                            }
                        }
                    }
                SplitView {
                    id: workspaceSplit
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                    orientation: Qt.Horizontal
                    onResizingChanged: if (!resizing && backend.sidebarExpanded) backend.setSidebarWidth(Math.round(sidebar.width))
                    handle: Rectangle {
                        implicitWidth: 10
                        color: SplitHandle.pressed ? root.alphaColor(root.c.accent, .46) : SplitHandle.hovered ? root.alphaColor(root.c.accent, .24) : "transparent"
                        Rectangle { anchors.centerIn: parent; width: 2; height: 42; radius: 1; color: parent.SplitHandle.hovered || parent.SplitHandle.pressed ? root.c.accent : root.alphaColor(root.c.text, .18) }
                        Behavior on color { ColorAnimation { duration: root.motion } }
                    }
                    Panel {
                        id: sidebar
                        SplitView.minimumWidth: backend.sidebarExpanded ? 230 : 64
                        SplitView.maximumWidth: backend.sidebarExpanded ? 420 : 64
                        SplitView.preferredWidth: backend.sidebarExpanded ? backend.sidebarWidth : 64
                        color: root.strongSurface
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 9; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                AppButton { visible: backend.sidebarExpanded; text: "People"; quiet: true; selected: !root.favoritesOnly; Layout.preferredWidth: 76; onClicked: root.favoritesOnly = false }
                                AppButton { visible: backend.sidebarExpanded; text: "Favorites"; quiet: true; selected: root.favoritesOnly; Layout.preferredWidth: 88; onClicked: root.favoritesOnly = true }
                                Item { Layout.fillWidth: true }
                                AppButton { Layout.preferredWidth: 42; text: backend.sidebarExpanded ? "‹" : "›"; font.pixelSize: 20; ToolTip.visible: hovered; ToolTip.text: backend.sidebarExpanded ? "Collapse people" : "Expand people"; onClicked: backend.toggleSidebar() }
                            }
                            RowLayout {
                                visible: backend.sidebarExpanded; Layout.fillWidth: true; spacing: 6
                                AppField { id: contactSearch; Layout.fillWidth: true; placeholderText: "Add by username"; onAccepted: backend.addContact(text) }
                                AppButton { text: "+"; accent: true; Layout.preferredWidth: 42; ToolTip.visible: hovered; ToolTip.text: "Add by username"; onClicked: backend.addContact(contactSearch.text) }
                            }
                            ListView {
                                id: contactList
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 5; clip: true
                                model: root.favoritesOnly ? backend.favoriteContacts : backend.contacts
                                AppText { anchors.centerIn: parent; visible: contactList.count === 0; width: Math.max(0, parent.width - 20); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: root.favoritesOnly ? "No favorites yet\nStar someone from their profile." : "No contacts yet"; color: root.c.muted; font.pixelSize: 11 }
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
                                delegate: AppButton {
                                    id: contactButton
                                    required property var modelData
                                    width: ListView.view.width; height: 44
                                    accent: backend.selectedSigningKey === modelData.signing_key
                                    leftPadding: 8; rightPadding: 10
                                    contentItem: RowLayout {
                                        spacing: 9
                                        Rectangle {
                                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 14
                                            color: contactButton.accent ? root.c.bg : root.c.hover
                                            AppText {
                                                anchors.centerIn: parent
                                                text: modelData.initials
                                                color: contactButton.accent ? root.c.accent : root.c.text
                                                font.pixelSize: 10; font.bold: true
                                            }
                                            StatusBadge { status: modelData.presence; size: 11; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.rightMargin: -2; anchors.bottomMargin: -2 }
                                        }
                                        AppText {
                                            visible: backend.sidebarExpanded
                                            Layout.fillWidth: true
                                            text: modelData.displayName
                                            font.family: modelData.displayFont
                                            color: contactButton.textColor; font.pixelSize: 13; font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Rectangle {
                                            visible: modelData.unread > 0
                                            Layout.preferredWidth: Math.max(18, unreadLabel.implicitWidth + 10); Layout.preferredHeight: 18
                                            radius: 9; color: root.c.danger
                                            AppText { id: unreadLabel; anchors.centerIn: parent; text: modelData.unread > 99 ? "99+" : modelData.unread; color: "white"; font.pixelSize: 9; font.bold: true }
                                        }
                                    }
                                    onClicked: backend.selectContact(modelData.signing_key)
                                }
                            }
                            Item { Layout.preferredHeight: 56 }
                        }
                    }
                    Panel {
                        SplitView.fillWidth: true
                        SplitView.minimumWidth: 500
                        color: root.softSurface
                        Loader { anchors.fill: parent; anchors.margins: 18; sourceComponent: backend.page === "server" ? serverView : backend.page === "settings" ? settingsView : backend.page === "contact" ? contactView : backend.page === "friends" ? friendsView : chatView }
                    }
                }
                }
            }

            Panel {
                id: identityBar
                x: 97; y: parent.height - height - 23; width: backend.sidebarExpanded ? Math.max(46, sidebar.width - 18) : 46; height: 50
                color: root.alphaColor(root.c.tile, .96); z: 10; clip: true
                Behavior on width { NumberAnimation { duration: root.motion; easing.type: Easing.OutCubic } }
                RowLayout {
                    anchors.fill: parent; anchors.margins: 5; spacing: 7
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 8; color: identityArea.containsMouse ? root.c.hover : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 5; spacing: 8
                            Avatar { size: 36 }
                            ColumnLayout { visible: backend.sidebarExpanded; spacing: 0; Layout.fillWidth: true
                                AppText { text: backend.displayName; font.family: backend.displayFont; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                RowLayout { spacing: 5; Rectangle { width: 7; height: 7; radius: 4; color: backend.presenceColor } AppText { text: backend.presence; font.pixelSize: 10 } }
                            }
                        }
                        MouseArea { id: identityArea; anchors.fill: parent; hoverEnabled: true; onClicked: profilePopup.open() }
                    }
                    AppButton { visible: backend.sidebarExpanded; Layout.preferredWidth: 40; text: "⚙"; font.pixelSize: 17; ToolTip.visible: hovered; ToolTip.text: "User Settings"; onClicked: backend.openSettingsTab("My Profile") }
                }
            }

            Popup {
                id: profilePopup; x: 20; y: parent.height - height - 82; width: 310; height: 355
                padding: 0; modal: false; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                background: Item {
                    Panel { anchors.fill: parent; color: root.c.bg; border.width: 1; border.color: root.c.tile }
                    AnimatedImage { anchors.fill: parent; source: backend.profileBackgroundUrl; fillMode: Image.PreserveAspectCrop; visible: source !== ""; opacity: .3 }
                }
                contentItem: ColumnLayout {
                    spacing: 0
                    Item { Layout.fillWidth: true; Layout.preferredHeight: 78
                        Rectangle { anchors.fill: parent; color: backend.bannerColor; radius: 12 }
                        AnimatedImage { anchors.fill: parent; source: backend.profileBannerUrl; fillMode: Image.PreserveAspectCrop; visible: source !== "" }
                    }
                    Item { Layout.fillWidth: true; Layout.preferredHeight: 16 }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 16; spacing: 7
                        Item {
                            Layout.preferredWidth: 66; Layout.preferredHeight: 66; Layout.topMargin: -60
                            Avatar { anchors.fill: parent; size: 66 }
                            Rectangle { anchors.fill: parent; radius: 33; color: avatarEdit.containsMouse ? "#88000000" : "transparent"; Behavior on color { ColorAnimation { duration: root.motion } } }
                            AppText { anchors.centerIn: parent; visible: avatarEdit.containsMouse; text: "✎"; font.pixelSize: 22; font.bold: true }
                            MouseArea { id: avatarEdit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { profilePopup.close(); backend.openSettingsTab("My Profile") } ToolTip.visible: containsMouse; ToolTip.text: "Edit profile" }
                        }
                        AppText { text: backend.displayName; font.family: backend.displayFont; font.pixelSize: 17; font.bold: true }
                        RowLayout { spacing: 7
                            AppText { text: "@" + backend.username; color: root.c.muted; font.pixelSize: 12 }
                            AppText { visible: backend.pronouns !== ""; text: "•  " + backend.pronouns; color: root.c.muted; font.pixelSize: 11 }
                        }
                        AppText { text: (backend.statusEmoji ? backend.statusEmoji + "  " : "") + backend.customStatus; visible: backend.customStatus !== "" || backend.statusEmoji !== ""; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        AppText { text: "ABOUT ME"; color: root.c.muted; font.pixelSize: 9; font.bold: true; Layout.topMargin: 5 }
                        AppText { text: backend.bio || "No About Me yet."; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Item { Layout.fillHeight: true }
                        AppButton { Layout.fillWidth: true; text: "●  " + backend.presence + "   ▾"; textColor: backend.presenceColor; onClicked: presencePopup.open() }
                    }
                }
            }
            Popup {
                id: presencePopup; parent: root.contentItem; x: 36; y: root.height - height - 94; width: 270; height: 190; padding: 7
                background: Panel { color: root.c.tile }
                contentItem: ColumnLayout {
                    Repeater {
                        model: ["Online", "Away", "Invisible", "Do Not Disturb"]
                        AppButton {
                            required property string modelData; Layout.fillWidth: true; quiet: true; text: "●   " + modelData
                            textColor: ({"Online":"#23a55a", "Away":"#f0b232", "Invisible":"#80848e", "Do Not Disturb":"#f23f43"})[modelData]
                            onClicked: { backend.setPresence(modelData); presencePopup.close(); profilePopup.close() }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: chatView
        ColumnLayout {
            id: chatRoot
            property string searchQuery: ""
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout { spacing: 2
                    AppText { text: backend.selectedName ? backend.selectedDisplayName : "Choose someone to start"; font.family: backend.selectedDisplayFont; font.pixelSize: 21; font.bold: true }
                    AppText { visible: backend.selectedName !== "" && backend.selectedDisplayName !== backend.selectedName; text: "@" + backend.selectedName; color: root.c.muted; font.pixelSize: 10 }
                    AppText { text: backend.selectedName ? "End-to-end encrypted. Open Profile to verify identity." : "Messages are encrypted before leaving this device."; color: root.c.muted; font.pixelSize: 13 }
                }
                Item { Layout.fillWidth: true }
                RowLayout {
                    visible: backend.selectedName !== ""; Layout.alignment: Qt.AlignTop; spacing: 6
                    AppField { Layout.preferredWidth: 190; implicitHeight: 36; placeholderText: "Search messages"; onTextChanged: chatRoot.searchQuery = text.toLowerCase() }
                    AppButton { text: "Profile"; Layout.preferredHeight: 36; ToolTip.visible: hovered; ToolTip.text: "View identity and safety number"; onClicked: backend.openPage("contact") }
                }
            }
            ListView {
                id: history; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: root.compactMessages ? 3 : 9
                model: backend.messages
                Rectangle { parent: history; anchors.fill: parent; color: root.alphaColor(root.messageSurface, backend.messageBackgroundOpacity); radius: root.corner; z: -1 }
                onCountChanged: Qt.callLater(positionViewAtEnd)
                header: Item {
                    width: history.width; height: history.count === 0 ? Math.max(180, history.height * .65) : 0
                    ColumnLayout { anchors.centerIn: parent; visible: history.count === 0; spacing: 7
                        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 62; height: 62; radius: 31; color: root.c.tile; AppText { anchors.centerIn: parent; text: backend.selectedName ? backend.selectedDisplayName.slice(0,2).toUpperCase() : "✦"; font.family: backend.selectedDisplayFont; font.pixelSize: 21; font.bold: true } StatusBadge { visible: backend.selectedName !== ""; status: backend.selectedPresence; size: 18; anchors.right: parent.right; anchors.bottom: parent.bottom } }
                        AppText { Layout.alignment: Qt.AlignHCenter; text: backend.selectedName ? "Start your conversation with " + backend.selectedDisplayName : "Choose someone from People"; font.family: backend.selectedName ? backend.selectedDisplayFont : "Segoe UI"; font.pixelSize: 16; font.bold: true }
                        AppText { Layout.alignment: Qt.AlignHCenter; text: backend.selectedName ? "Your first message will be encrypted before it leaves this device." : "Add a username or select the demo account to begin."; color: root.c.muted; font.pixelSize: 11 }
                    }
                }
                delegate: Rectangle {
                    id: messageRow
                    required property var modelData
                    width: ListView.view.width
                    property bool matchesSearch: chatRoot.searchQuery === "" || modelData.searchText.indexOf(chatRoot.searchQuery) >= 0
                    visible: matchesSearch
                    height: visible ? messageLayout.implicitHeight + (root.compactMessages ? 8 : 16) + (modelData.showDate ? 30 : 0) : 0
                    color: messageHover.hovered ? root.alphaColor(root.c.tile, .48) : "transparent"
                    radius: 7
                    Behavior on color { ColorAnimation { duration: root.motion } }
                    RowLayout {
                        visible: messageRow.modelData.showDate
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 26; spacing: 10
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.c.hover }
                        AppText { text: messageRow.modelData.dateLabel; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.c.hover }
                    }
                    RowLayout {
                        id: messageLayout; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.leftMargin: 10; anchors.rightMargin: 8; anchors.topMargin: root.compactMessages ? 4 : 8; anchors.bottomMargin: root.compactMessages ? 4 : 8; spacing: 10
                        Item {
                            id: messageAvatar
                            visible: !root.compactMessages; Layout.preferredWidth: 38; Layout.preferredHeight: 38
                            scale: avatarProfileArea.containsMouse ? 1.06 : 1
                            Behavior on scale { NumberAnimation { duration: root.motion; easing.type: Easing.OutCubic } }
                            Avatar {
                                anchors.fill: parent; size: 38
                                initials: messageRow.modelData.outgoing ? backend.displayName.slice(0,2).toUpperCase() : backend.selectedDisplayName.slice(0,2).toUpperCase()
                                status: messageRow.modelData.outgoing ? backend.presence : backend.selectedPresence
                                source: messageRow.modelData.outgoing ? backend.avatarUrl : ""
                            }
                            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: avatarProfileArea.containsMouse ? 2 : 0; border.color: root.c.accent }
                            MouseArea { id: avatarProfileArea; anchors.fill: parent; enabled: !messageRow.modelData.outgoing; hoverEnabled: true; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: backend.openPage("contact") }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            RowLayout {
                                Layout.fillWidth: true; spacing: 7
                                AppText {
                                    text: messageRow.modelData.sender; color: senderProfileArea.containsMouse ? root.c.text : root.c.accent; font.family: messageRow.modelData.senderFont; font.pixelSize: Math.round(12 * root.uiScale); font.bold: true; font.underline: senderProfileArea.containsMouse
                                    Behavior on color { ColorAnimation { duration: root.motion } }
                                    MouseArea { id: senderProfileArea; anchors.fill: parent; enabled: !messageRow.modelData.outgoing; hoverEnabled: true; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: backend.openPage("contact") }
                                }
                                AppText { text: messageRow.modelData.timestamp; color: root.c.muted; font.pixelSize: Math.round(11 * root.uiScale); ToolTip.visible: timestampHover.containsMouse; ToolTip.text: messageRow.modelData.fullTimestamp; MouseArea { id: timestampHover; anchors.fill: parent; hoverEnabled: true } }
                                Item { Layout.fillWidth: true }
                            }
                            Text { Layout.fillWidth: true; text: messageRow.modelData.body; textFormat: Text.RichText; color: root.c.text; font.family: "Segoe UI"; font.pixelSize: Math.round(15 * root.uiScale); font.hintingPreference: Font.PreferFullHinting; wrapMode: Text.Wrap; renderType: Text.NativeRendering }
                            Repeater {
                                model: messageRow.modelData.attachments
                                ColumnLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; spacing: 5; Layout.topMargin: 4
                                    Image {
                                        id: attachmentPreview; visible: source !== ""; source: modelData.previewUrl
                                        Layout.preferredWidth: Math.min(320, implicitWidth); Layout.preferredHeight: visible ? Math.min(220, implicitHeight) : 0
                                        fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false
                                        MouseArea { anchors.fill: parent; enabled: attachmentPreview.status === Image.Ready; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: imageViewer.showImage(attachmentPreview.source) }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        AppText { text: modelData.name; font.bold: true; elide: Text.ElideMiddle; Layout.maximumWidth: 300 }
                                        AppText { text: modelData.sizeLabel; color: root.c.muted; font.pixelSize: 10 }
                                        AppButton { text: modelData.available ? "Save" : "Retry"; quiet: true; Layout.preferredWidth: 52; Layout.preferredHeight: 28; onClicked: backend.saveAttachment(messageRow.modelData.id, index) }
                                    }
                                }
                            }
                        }
                        AppButton { visible: messageHover.hovered && messageRow.modelData.plainText !== ""; text: "Copy"; quiet: true; Layout.preferredWidth: 54; Layout.preferredHeight: 30; onClicked: backend.copyText(messageRow.modelData.plainText) }
                    }
                    HoverHandler { id: messageHover }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
            RowLayout {
                id: typingIndicator
                visible: backend.selectedTyping
                Layout.leftMargin: 8; Layout.bottomMargin: 1; spacing: 5
                AppText { text: backend.selectedDisplayName + " is typing"; color: root.c.muted; font.family: backend.selectedDisplayFont; font.pixelSize: 11 }
                Repeater {
                    model: 3
                    Rectangle {
                        width: 5; height: 5; radius: 3; color: root.c.accent; opacity: .3
                        SequentialAnimation on opacity {
                            running: typingIndicator.visible; loops: Animation.Infinite
                            PauseAnimation { duration: index * 140 }
                            NumberAnimation { to: 1; duration: 180 }
                            NumberAnimation { to: .3; duration: 180 }
                            PauseAnimation { duration: (2 - index) * 140 }
                        }
                    }
                }
            }
            Panel {
                id: composerPanel
                Layout.fillWidth: true; Layout.preferredHeight: backend.pendingAttachments.length > 0 ? 146 : 108; color: root.alphaColor(root.mixColor(root.c.tile, root.buttonSurface, .18), Math.max(.9, backend.controlOpacity)); radius: 10
                border.width: 1; border.color: root.alphaColor(root.mixColor(root.c.text, root.buttonSurface, .5), .28)
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 7; spacing: 4
                    RowLayout {
                        spacing: 2
                        AppButton { visible: backend.settings.show_formatting_buttons === true; text: "B"; quiet: true; font.bold: true; Layout.preferredWidth: 30; Layout.preferredHeight: 28; onClicked: composerPanel.format("**") }
                        AppButton { visible: backend.settings.show_formatting_buttons === true; text: "I"; quiet: true; font.italic: true; Layout.preferredWidth: 30; Layout.preferredHeight: 28; onClicked: composerPanel.format("*") }
                        AppButton { visible: backend.settings.show_formatting_buttons === true; text: "</>"; quiet: true; Layout.preferredWidth: 38; Layout.preferredHeight: 28; onClicked: composerPanel.format("`") }
                        AppButton { visible: backend.settings.show_formatting_buttons === true; text: "Code"; quiet: true; Layout.preferredWidth: 46; Layout.preferredHeight: 28; onClicked: composerPanel.format("```") }
                        AppButton { text: "Attach"; quiet: true; Layout.preferredWidth: 58; Layout.preferredHeight: 28; enabled: backend.selectedName !== ""; onClicked: backend.chooseAttachments() }
                        Item { Layout.fillWidth: true }
                        AppText { visible: backend.status !== ""; text: backend.status; color: backend.status.indexOf("WARNING") >= 0 || backend.status.indexOf("Not sent") === 0 ? root.c.danger : root.c.muted; font.pixelSize: 10; elide: Text.ElideRight; Layout.maximumWidth: 280 }
                        AppText { text: composer.length + " / 4000"; color: composer.length > 3800 ? root.c.danger : root.c.muted; font.pixelSize: 10 }
                    }
                    RowLayout {
                        visible: backend.pendingAttachments.length > 0; Layout.fillWidth: true; Layout.preferredHeight: visible ? 32 : 0; spacing: 5
                        Repeater {
                            model: backend.pendingAttachments
                            Rectangle {
                                required property var modelData
                                required property int index
                                Layout.preferredWidth: Math.min(185, attachmentName.implicitWidth + attachmentSize.implicitWidth + 42); Layout.preferredHeight: 30
                                radius: 7; color: root.c.panel
                                RowLayout { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 5; spacing: 5
                                    AppText { id: attachmentName; Layout.fillWidth: true; text: modelData.name; font.pixelSize: 11; elide: Text.ElideMiddle }
                                    AppText { id: attachmentSize; text: modelData.sizeLabel; color: root.c.muted; font.pixelSize: 9 }
                                    AppButton { text: "×"; quiet: true; Layout.preferredWidth: 24; Layout.preferredHeight: 24; onClicked: backend.removeAttachment(index) }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                        TextArea {
                            id: composer; Layout.fillWidth: true; Layout.fillHeight: true
                            color: root.c.text; placeholderText: backend.selectedName ? "Message " + backend.selectedDisplayName : "Choose a contact first"; placeholderTextColor: root.c.muted
                            font.family: "Segoe UI"; font.pixelSize: Math.round(15 * root.uiScale); font.hintingPreference: Font.PreferFullHinting; wrapMode: TextEdit.Wrap; padding: 10
                            onTextChanged: {
                                if (length > 4000) remove(4000, length)
                                backend.setTyping(length > 0 && activeFocus)
                            }
                            onActiveFocusChanged: backend.setTyping(length > 0 && activeFocus)
                            background: Rectangle { color: "transparent"; radius: 8; border.width: composer.activeFocus ? 1 : 0; border.color: root.c.accent }
                            Keys.onReturnPressed: function(event) {
                                var shouldSend = backend.enterToSend ? !(event.modifiers & Qt.ShiftModifier) : (event.modifiers & Qt.ControlModifier)
                                if (shouldSend) { backend.sendMessage(text); text = ""; event.accepted = true }
                            }
                        }
                        AppButton { visible: backend.settings.show_send_button === true; text: "Send"; accent: true; Layout.preferredWidth: 68; Layout.fillHeight: true; enabled: backend.selectedName !== "" && (composer.length > 0 || backend.pendingAttachments.length > 0); onClicked: { backend.sendMessage(composer.text); composer.text = "" } }
                    }
                }
                function format(marker) {
                    var start = composer.selectionStart, end = composer.selectionEnd
                    var selected = composer.text.substring(start, end)
                    var edge = marker === "```" ? "\n" : ""
                    var contentStart = start + marker.length + edge.length
                    composer.remove(start, end)
                    composer.insert(start, marker + edge + selected + edge + marker)
                    composer.forceActiveFocus()
                    if (selected.length > 0)
                        composer.select(contentStart, contentStart + selected.length)
                    else
                        composer.cursorPosition = contentStart
                }
            }
        }
    }

    Component {
        id: serverView
        SplitView {
            orientation: Qt.Horizontal; spacing: 0
            onResizingChanged: if (!resizing) { backend.setServerChannelWidth(Math.round(serverChannels.width)); backend.setServerMemberWidth(Math.round(serverMembers.width)) }
            handle: Rectangle { implicitWidth: 9; color: SplitHandle.pressed ? root.alphaColor(root.c.accent, .42) : SplitHandle.hovered ? root.alphaColor(root.c.accent, .2) : "transparent"
                Rectangle { anchors.centerIn: parent; width: 2; height: 40; radius: 1; color: parent.SplitHandle.hovered || parent.SplitHandle.pressed ? root.c.accent : root.alphaColor(root.c.text, .16) }
            }
            Panel {
                id: serverChannels; SplitView.minimumWidth: 180; SplitView.maximumWidth: 360; SplitView.preferredWidth: backend.serverChannelWidth; color: root.strongSurface
                ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 8
                    RowLayout { Layout.fillWidth: true
                        AppText { text: backend.selectedServer.name || "Server"; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        AppButton { text: "•••"; quiet: true; Layout.preferredWidth: 38; ToolTip.visible: hovered; ToolTip.text: "Server menu"; onClicked: serverActionsMenu.popup() }
                        AppMenu { id: serverActionsMenu
                            AppMenuItem { text: "Create invite"; onTriggered: invitePopup.open() }
                            AppMenuItem { text: "Server settings"; onTriggered: serverSettings.open() }
                        }
                    }
                    SectionLabel { text: "TEXT CHANNELS" }
                    ListView { Layout.fillWidth: true; Layout.fillHeight: true; model: backend.selectedServer.channels || []; spacing: 4
                        delegate: AppButton { required property var modelData; visible: modelData.type === "text"; width: ListView.view.width; text: "#  " + modelData.name; quiet: true; selected: backend.selectedChannelId === modelData.id; onClicked: backend.selectServerChannel(modelData.id) }
                    }
                    AppField { id: newChannelName; Layout.fillWidth: true; placeholderText: "new-channel"; onAccepted: { backend.createServerChannel(text); text = "" } }
                    AppButton { text: "Create channel"; Layout.fillWidth: true; onClicked: { backend.createServerChannel(newChannelName.text); newChannelName.text = "" } }
                }
            }
            Item { SplitView.minimumWidth: 380; SplitView.fillWidth: true
              ColumnLayout { anchors.fill: parent; spacing: 10
                RowLayout { Layout.fillWidth: true
                    AppText { text: "# " + (backend.selectedChannel.name || "channel"); font.pixelSize: 21; font.bold: true }
                    Item { Layout.fillWidth: true }
                    AppText { text: (backend.selectedServer.members || []).length + " members"; color: root.c.muted; font.pixelSize: 12 }
                }
                Panel { Layout.fillWidth: true; Layout.fillHeight: true; color: root.alphaColor(root.messageSurface, backend.messageBackgroundOpacity)
                    ListView { anchors.fill: parent; anchors.margins: 14; clip: true; spacing: 9; model: backend.serverMessages
                        delegate: Column { required property var modelData; width: ListView.view.width
                            AppText { text: modelData.sender + "  " + modelData.timestamp; color: modelData.outgoing ? root.c.accent : root.c.text; font.bold: true }
                            AppText { text: modelData.text; width: parent.width; wrapMode: Text.Wrap; font.pixelSize: 14 }
                        }
                    }
                }
                RowLayout { Layout.fillWidth: true
                    AppField { id: serverComposer; Layout.fillWidth: true; placeholderText: "Message #" + (backend.selectedChannel.name || "channel"); onAccepted: { backend.sendServerMessage(text); text = "" } }
                    AppButton { text: "Send"; accent: true; onClicked: { backend.sendServerMessage(serverComposer.text); serverComposer.text = "" } }
                }
                AppText { visible: backend.status !== ""; text: backend.status; color: root.c.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
              }
            }
            Panel { id: serverMembers; SplitView.minimumWidth: 190; SplitView.maximumWidth: 360; SplitView.preferredWidth: backend.serverMemberWidth; color: root.strongSurface; radius: root.corner
                ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 8
                    AppText { text: "Members"; font.pixelSize: 17; font.bold: true }
                    AppText { text: (backend.selectedServer.members || []).length + " people"; color: root.c.muted; font.pixelSize: 11 }
                    ListView { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 10; model: backend.serverMemberGroups
                        delegate: Column { required property var modelData; width: ListView.view.width; spacing: 5
                            AppText { text: modelData.name.toUpperCase() + " — " + modelData.members.length; color: modelData.color; font.pixelSize: 11; font.bold: true }
                            Repeater { model: modelData.members
                                Row { required property var modelData; width: parent.width; height: 38; spacing: 8
                                    Rectangle { width: 30; height: 30; radius: 15; color: root.c.tile
                                        AppText { anchors.centerIn: parent; text: modelData.initials; font.pixelSize: 10; font.bold: true }
                                        StatusBadge { anchors.right: parent.right; anchors.bottom: parent.bottom; size: 10; status: modelData.status }
                                    }
                                    Column { width: parent.width - 38; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                                        AppText { text: modelData.name; width: parent.width; elide: Text.ElideRight; font.pixelSize: 13; font.bold: true; opacity: modelData.status === "Offline" ? .58 : 1 }
                                        AppText { text: "@" + modelData.username; width: parent.width; elide: Text.ElideRight; color: root.c.muted; font.pixelSize: 10; visible: modelData.status !== "Offline" }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Popup { id: invitePopup; parent: Overlay.overlay; anchors.centerIn: parent; width: Math.min(500, root.width - 32); height: Math.min(570, root.height - 32); modal: true; focus: true; padding: 20
                property var selectedKeys: []
                function toggleRecipient(key, enabled) { var values = selectedKeys.slice(); var index = values.indexOf(key); if (enabled && index < 0) values.push(key); else if (!enabled && index >= 0) values.splice(index, 1); selectedKeys = values }
                onOpened: { selectedKeys = []; quickInviteCode.text = backend.newInviteCode(); quickInviteExpiry.currentIndex = 2 }
                background: Rectangle { color: root.c.panel; radius: root.corner; border.color: root.alphaColor(root.c.text, .18) }
                ColumnLayout { anchors.fill: parent; spacing: 10
                    RowLayout { Layout.fillWidth: true; AppText { text: "Invite people to " + (backend.selectedServer.name || "server"); font.pixelSize: 20; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight } AppButton { text: "Close"; quiet: true; onClicked: invitePopup.close() } }
                    SectionLabel { text: "UNIQUE INVITE CODE" }
                    RowLayout { Layout.fillWidth: true
                        AppField { id: quickInviteCode; Layout.fillWidth: true; readOnly: true }
                        AppButton { text: "New code"; onClicked: quickInviteCode.text = backend.newInviteCode() }
                    }
                    RowLayout { Layout.fillWidth: true; AppText { text: "Expires"; color: root.c.muted } AppComboBox { id: quickInviteExpiry; Layout.fillWidth: true; model: ["1 day", "7 days", "Forever"] } }
                    SectionLabel { text: "QUICK INVITE CONTACTS" }
                    AppText { text: "Select people you have added. Their invite is sent as an encrypted system message."; color: root.c.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    ListView { id: quickInviteList; Layout.fillWidth: true; Layout.fillHeight: true; model: backend.invitableContacts; clip: true; spacing: 5
                        delegate: Rectangle { required property var modelData; width: ListView.view.width; height: 48; radius: 8; color: root.c.tile
                            RowLayout { anchors.fill: parent; anchors.margins: 9
                                CheckBox { checked: invitePopup.selectedKeys.indexOf(modelData.signing_key) >= 0; onToggled: invitePopup.toggleRecipient(modelData.signing_key, checked) }
                                AppText { text: modelData.displayName; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                AppText { text: "@" + modelData.name; color: root.c.muted }
                            }
                        }
                    }
                    AppButton { text: invitePopup.selectedKeys.length ? "Create and send invite" : "Create invite"; accent: true; Layout.fillWidth: true; onClicked: { backend.createServerInviteWithOptions(quickInviteCode.text, quickInviteExpiry.currentText, invitePopup.selectedKeys); invitePopup.close() } }
                }
            }
            Popup {
                id: serverSettings; parent: Overlay.overlay; anchors.centerIn: parent; width: Math.min(620, root.width - 32); height: Math.min(640, root.height - 32); modal: true; focus: true; padding: 20
                background: Rectangle { color: root.c.panel; radius: root.corner; border.color: root.alphaColor(root.c.text, .16) }
                ColumnLayout { anchors.fill: parent; spacing: 10
                    RowLayout { Layout.fillWidth: true; AppText { text: "Server settings"; font.pixelSize: 22; font.bold: true } Item { Layout.fillWidth: true } AppButton { text: "Close"; quiet: true; onClicked: serverSettings.close() } }
                    ScrollView { id: settingsScroll; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ColumnLayout { width: settingsScroll.availableWidth; spacing: 10
                            SectionLabel { text: "CUSTOMISATION" }
                            AppField { id: serverNameEdit; Layout.fillWidth: true; text: backend.selectedServer.name || ""; placeholderText: "Server name" }
                            AppField { id: serverAccentEdit; Layout.fillWidth: true; text: backend.selectedServer.accent || root.c.accent; placeholderText: "Accent color, e.g. #5865f2" }
                            RowLayout { Layout.fillWidth: true
                                AppButton { text: "Choose server icon"; onClicked: backend.chooseServerIcon() }
                                AppButton { text: "Save appearance"; accent: true; onClicked: backend.updateServer(serverNameEdit.text, serverAccentEdit.text) }
                                Item { Layout.fillWidth: true }
                            }
                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.alphaColor(root.c.text, .14) }
                            SectionLabel { text: "CUSTOM INVITE" }
                            AppField { id: customInviteCode; Layout.fillWidth: true; placeholderText: "Custom invite code" }
                            RowLayout { Layout.fillWidth: true; AppText { text: "Expires"; color: root.c.muted } AppComboBox { id: customInviteExpiry; Layout.fillWidth: true; model: ["1 day", "7 days", "Forever"]; currentIndex: 2 } }
                            AppButton { text: "Create custom invite"; accent: true; enabled: customInviteCode.text.trim().length >= 4; onClicked: { backend.createServerInviteWithOptions(customInviteCode.text, customInviteExpiry.currentText, []); customInviteCode.text = "" } }
                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.alphaColor(root.c.text, .14) }
                            SectionLabel { text: "ROLES AND RULES" }
                            AppField { id: roleNameEdit; Layout.fillWidth: true; placeholderText: "Custom role name" }
                            AppField { id: roleColorEdit; Layout.fillWidth: true; text: "#94a3b8"; placeholderText: "Role color" }
                            Flow { id: permissionFlow; Layout.fillWidth: true; spacing: 6
                                Repeater { model: backend.serverPermissions
                                    CheckBox { required property string modelData; text: modelData.replace(/_/g, " "); palette.windowText: root.c.text; checked: modelData === "view_channels" || modelData === "send_messages" }
                                }
                            }
                            AppButton { text: "Create custom role"; accent: true; onClicked: { var values = []; for (var i = 0; i < permissionFlow.children.length; ++i) if (permissionFlow.children[i].checked) values.push(permissionFlow.children[i].modelData); backend.createServerRole(roleNameEdit.text, roleColorEdit.text, values); roleNameEdit.text = "" } }
                            SectionLabel { text: "EXISTING ROLES" }
                            ListView { Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight, 150); model: backend.selectedServer.roles || []; clip: true; spacing: 5; interactive: contentHeight > height
                                delegate: Rectangle { required property var modelData; width: ListView.view.width; height: 48; radius: 8; color: root.c.tile
                                    RowLayout { anchors.fill: parent; anchors.margins: 5; spacing: 7
                                        Rectangle { width: 12; height: 12; radius: 6; color: modelData.color }
                                        AppField { id: roleRenameField; Layout.fillWidth: true; text: modelData.name; font.bold: true; onAccepted: backend.renameServerRole(modelData.id, text) }
                                        AppButton { text: "Rename"; onClicked: backend.renameServerRole(modelData.id, roleRenameField.text) }
                                    }
                                }
                            }
                            SectionLabel { text: "MEMBERS" }
                            AppText { text: "Admins can assign roles through the member list below."; color: root.c.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            ListView { Layout.fillWidth: true; Layout.preferredHeight: Math.min(Math.max(contentHeight, 48), 150); model: backend.selectedServer.members || []; clip: true; interactive: contentHeight > height
                                delegate: RowLayout { required property var modelData; property var memberData: modelData; width: ListView.view.width; height: 44
                                    AppText { text: "@" + memberData.card.name; Layout.fillWidth: true; elide: Text.ElideRight }
                                    AppText { text: memberData.roles.join(", "); color: root.c.muted; elide: Text.ElideRight; Layout.maximumWidth: 130 }
                                    AppComboBox { Layout.preferredWidth: 150; model: backend.selectedServer.roles || []; textRole: "name"; enabled: memberData.signing_key !== backend.selectedServer.owner_key; onActivated: backend.setServerMemberRoles(memberData.signing_key, [model[index].id]) }
                                }
                            }
                            Rectangle { visible: backend.selectedServerOwned; Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.alphaColor(root.c.danger, .45) }
                            SectionLabel { visible: backend.selectedServerOwned; text: "DANGER ZONE"; color: root.c.danger }
                            AppButton { visible: backend.selectedServerOwned; text: "Delete server"; danger: true; onClicked: deleteServerWarning.open() }
                            Item { Layout.preferredHeight: 4 }
                        }
                    }
                }
            }
            Popup { id: deleteServerWarning; parent: Overlay.overlay; anchors.centerIn: parent; width: Math.min(440, root.width - 32); modal: true; focus: true; padding: 22
                background: Rectangle { color: root.c.panel; radius: root.corner; border.color: root.c.danger; border.width: 1 }
                ColumnLayout { width: parent.width; spacing: 12
                    AppText { text: "Delete “" + (backend.selectedServer.name || "server") + "”?"; font.pixelSize: 20; font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    AppText { text: "This permanently deletes the server, its channels, roles, invites, and membership for everyone. This cannot be undone."; color: root.c.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } AppButton { text: "Cancel"; quiet: true; onClicked: deleteServerWarning.close() } AppButton { text: "Delete permanently"; danger: true; onClicked: { deleteServerWarning.close(); serverSettings.close(); backend.deleteServer() } } }
                }
            }
        }
    }

    Component {
        id: friendsView
        ColumnLayout {
            spacing: 12
            RowLayout { Layout.fillWidth: true
                ColumnLayout { spacing: 2; AppText { text: "Friends"; font.pixelSize: 23; font.bold: true } AppText { text: "Your pinned encrypted contacts."; color: root.c.muted } }
                Item { Layout.fillWidth: true }
                AppButton { text: "Back to messages"; onClicked: backend.openPage("chat") }
            }
            GridView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                cellWidth: Math.max(220, width / Math.max(1, Math.floor(width / 260))); cellHeight: 92
                model: backend.favoriteContacts
                delegate: Item {
                    required property var modelData; width: GridView.view.cellWidth; height: 88
                    Rectangle { anchors.fill: parent; anchors.margins: 4; radius: root.corner; color: friendArea.containsMouse ? root.c.hover : root.alphaColor(root.c.tile, backend.controlOpacity)
                        RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 11
                            Rectangle { Layout.preferredWidth: 46; Layout.preferredHeight: 46; radius: 23; color: root.c.panel
                                AppText { anchors.centerIn: parent; text: modelData.initials; font.bold: true }
                                StatusBadge { status: modelData.presence; size: 14; anchors.right: parent.right; anchors.bottom: parent.bottom }
                            }
                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                AppText { text: modelData.displayName; font.family: modelData.displayFont; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                AppText { text: "@" + modelData.name; color: root.c.muted; font.pixelSize: 10 }
                                AppText { text: modelData.presence; color: root.c.muted; font.pixelSize: 10 }
                            }
                        }
                        MouseArea { id: friendArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: backend.selectContact(modelData.signing_key) }
                    }
                }
            }
        }
    }

    Component {
        id: contactView
        ColumnLayout {
            spacing: 14
            RowLayout { Layout.fillWidth: true; AppText { text: "Contact profile"; font.pixelSize: 22; font.bold: true } Item { Layout.fillWidth: true } AppButton { text: "Back to chat"; onClicked: backend.openPage("chat") } }
            Panel {
                Layout.fillWidth: true; Layout.preferredHeight: 440; color: root.c.bg; clip: true
                Rectangle { anchors.fill: parent; color: backend.selectedBannerColor; opacity: .14 }
                AnimatedImage { anchors.fill: parent; source: backend.selectedProfileBackgroundUrl; fillMode: Image.PreserveAspectCrop; visible: source !== ""; opacity: .3 }
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 112; color: backend.selectedBannerColor }
                AnimatedImage { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 112; source: backend.selectedProfileBannerUrl; fillMode: Image.PreserveAspectCrop; visible: source !== "" }
                ColumnLayout { anchors.fill: parent; anchors.margins: 26; anchors.topMargin: 66; spacing: 8
                    Avatar { size: 82; initials: backend.selectedIsDemo ? "BOT" : backend.selectedName.slice(0,2).toUpperCase(); status: backend.selectedPresence; source: backend.selectedAvatarUrl }
                    RowLayout { AppText { text: backend.selectedDisplayName; font.family: backend.selectedDisplayFont; font.pixelSize: 21; font.bold: true } AppText { visible: backend.selectedPronouns !== ""; text: backend.selectedPronouns; color: root.c.muted; font.pixelSize: 11 } }
                    AppText { text: "@" + backend.selectedName; color: root.c.muted }
                    AppText { visible: backend.selectedCustomStatus !== ""; text: (backend.selectedStatusEmoji ? backend.selectedStatusEmoji + "  " : "") + backend.selectedCustomStatus; font.family: backend.selectedDisplayFont; color: root.c.text }
                    AppText { visible: backend.selectedBio !== ""; text: backend.selectedBio; color: root.c.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    AppText { visible: backend.selectedBio === "" && backend.selectedCustomStatus === ""; text: backend.selectedIsDemo ? "Demo encrypted echo account" : "Secure Tiles contact"; color: root.c.muted }
                    RowLayout { Layout.topMargin: 8
                        AppButton { text: backend.selectedFavorite ? "★ Favorited" : "☆ Add favorite"; selected: backend.selectedFavorite; onClicked: backend.toggleFavoriteContact() }
                        AppField { id: contactNickname; Layout.preferredWidth: 220; placeholderText: "Local nickname"; text: backend.selectedNickname; maximumLength: 32 }
                        AppButton { text: "Save nickname"; onClicked: backend.setContactNickname(contactNickname.text) }
                    }
                    AppText { text: "SAFETY NUMBER"; color: root.c.muted; font.pixelSize: 10; font.bold: true; Layout.topMargin: 12 }
                    Rectangle { Layout.preferredWidth: safety.implicitWidth + 28; Layout.preferredHeight: 42; radius: 8; color: root.c.tile; AppText { id: safety; anchors.centerIn: parent; text: backend.safetyNumber; font.family: "Cascadia Mono"; font.bold: true } }
                    AppText { text: "Compare this number over a trusted channel before sharing sensitive information."; color: root.c.muted }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: settingsView
        ColumnLayout {
            spacing: 14
            RowLayout { Layout.fillWidth: true; AppText { text: "Settings"; font.pixelSize: 22; font.bold: true } AppText { text: "Personalize your Secure Tiles experience"; color: root.c.muted; font.pixelSize: 11 } Item { Layout.fillWidth: true } AppButton { text: "Back to messages"; onClicked: backend.openPage("chat") } }
            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                Panel {
                    Layout.preferredWidth: 184; Layout.fillHeight: true; color: root.strongSurface
                    ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 5
                        SectionLabel { text: "SETTINGS"; Layout.leftMargin: 9; Layout.topMargin: 5; Layout.bottomMargin: 3 }
                        Repeater { model: ["My Profile", "General", "Appearance", "Privacy", "Notifications", "About"]
                            Item {
                                required property string modelData
                                Layout.fillWidth: true; Layout.preferredHeight: 40
                                AppButton { anchors.fill: parent; text: parent.modelData; quiet: true; selected: backend.settingsTab === parent.modelData; leftPadding: 13; rightPadding: 10; contentItem: AppText { text: parent.text; color: parent.selected ? root.c.text : root.alphaColor(root.c.text, .76); font.pixelSize: 13; font.bold: parent.selected; horizontalAlignment: Text.AlignLeft; verticalAlignment: Text.AlignVCenter } onClicked: backend.openSettingsTab(parent.modelData) }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
                Panel {
                    Layout.fillWidth: true; Layout.fillHeight: true; color: root.alphaColor(root.c.panel, Math.max(.82, backend.panelOpacity)); radius: root.corner
                    Loader { anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; anchors.topMargin: 18; anchors.bottomMargin: 18; sourceComponent: backend.settingsTab === "My Profile" ? profileSettings : backend.settingsTab === "General" ? generalSettings : backend.settingsTab === "Appearance" ? appearanceSettings : backend.settingsTab === "Privacy" ? privacySettings : backend.settingsTab === "Notifications" ? notificationSettings : aboutSettings }
                }
            }
        }
    }

    Component {
        id: profileSettings
        Flickable {
            contentHeight: profileColumn.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: profileColumn; width: Math.min(parent.width, 760); x: Math.max(0, (parent.width - width) / 2); spacing: 8
                AppText { text: "Profile customization"; font.pixelSize: 19; font.bold: true }
                AppText { text: "Your unique username is @" + backend.username + ". It cannot be changed or reused."; color: root.c.muted }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 150; radius: 12; color: root.alphaColor(root.c.panel, .82); clip: true
                    border.width: 1; border.color: root.alphaColor(Qt.lighter(root.c.panel, 1.5), .18)
                    AnimatedImage { anchors.fill: parent; source: backend.profileBackgroundUrl; fillMode: Image.PreserveAspectCrop; visible: source !== ""; opacity: .42 }
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 76; color: backend.bannerColor }
                    AnimatedImage { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 76; source: backend.profileBannerUrl; fillMode: Image.PreserveAspectCrop; visible: source !== "" }
                    Avatar { size: 80; x: 18; y: 42 }
                    AppText { x: 112; y: 91; text: displayName.text || backend.displayName; font.family: displayFont.currentValue || backend.displayFont; font.pixelSize: 17; font.bold: true }
                    AppText { x: 112; y: 116; text: "@" + backend.username + (pronouns.text ? "  •  " + pronouns.text : ""); color: root.c.muted; font.pixelSize: 11 }
                }
                GridLayout { Layout.fillWidth: true; columns: width > 620 ? 4 : 2; columnSpacing: 7; rowSpacing: 7
                    AppButton { Layout.fillWidth: true; text: "Change avatar"; onClicked: backend.chooseAvatar() }
                    AppButton { Layout.fillWidth: true; text: "Banner image / GIF"; onClicked: backend.chooseProfileBanner() }
                    AppButton { Layout.fillWidth: true; text: "Profile background"; onClicked: backend.chooseProfileBackground() }
                    AppButton { Layout.fillWidth: true; text: "Banner color"; onClicked: backend.chooseBannerColor() }
                }
                RowLayout { visible: backend.profileBannerUrl !== "" || backend.profileBackgroundUrl !== ""; AppButton { text: "Remove banner image"; quiet: true; visible: backend.profileBannerUrl !== ""; onClicked: backend.clearMedia("profile_banner") } AppButton { text: "Remove profile background"; quiet: true; visible: backend.profileBackgroundUrl !== ""; onClicked: backend.clearMedia("profile_background") } }
                FieldLabel { text: "DISPLAY NAME" }
                AppField { id: displayName; Layout.fillWidth: true; text: backend.displayName; placeholderText: "How people see you" }
                FieldLabel { text: "DISPLAY NAME FONT" }
                AppComboBox {
                    id: displayFont; Layout.preferredWidth: 220; model: backend.displayFontOptions
                    textRole: "name"; valueRole: "family"; font.family: currentValue || backend.displayFont
                    Component.onCompleted: { for (var i = 0; i < count; ++i) if (valueAt(i) === backend.displayFont) { currentIndex = i; break } }
                    onActivated: backend.setDisplayFont(currentValue)
                }
                FieldLabel { text: "PRONOUNS" }
                AppField { id: pronouns; Layout.fillWidth: true; text: backend.pronouns; placeholderText: "Optional pronouns"; maximumLength: 40 }
                FieldLabel { text: "CUSTOM STATUS" }
                AppField { id: customStatus; Layout.fillWidth: true; text: backend.customStatus; placeholderText: "What are you up to?" }
                FieldLabel { text: "STATUS EMOJI" }
                AppField { id: statusEmoji; Layout.preferredWidth: 150; text: backend.statusEmoji; placeholderText: "e.g. 🎮"; maximumLength: 8 }
                FieldLabel { text: "ABOUT ME" }
                TextArea { id: bio; Layout.fillWidth: true; Layout.preferredHeight: 92; text: backend.bio; color: root.c.text; placeholderText: "Tell people about yourself"; placeholderTextColor: root.c.muted; wrapMode: TextEdit.Wrap; padding: 11; background: Rectangle { color: root.alphaColor(root.mixColor(root.c.bg, root.buttonSurface, .18), Math.max(.9, backend.controlOpacity)); radius: Math.max(4, root.corner - 2); border.width: bio.activeFocus ? 2 : 1; border.color: bio.activeFocus ? root.c.accent : root.alphaColor(root.mixColor(root.c.text, root.buttonSurface, .62), .55) } }
                AppButton { text: "Save profile"; accent: true; onClicked: backend.saveProfile(displayName.text, customStatus.text, bio.text, pronouns.text, backend.bannerColor, statusEmoji.text, displayFont.currentValue) }
                AppText { text: backend.status; color: root.c.muted; font.pixelSize: 11 }
            }
        }
    }

    Component {
        id: appearanceSettings
        Flickable {
          contentHeight: appearanceColumn.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
          ColumnLayout { id: appearanceColumn; width: Math.min(parent.width, 760); x: Math.max(0, (parent.width - width) / 2); spacing: 7
            AppText { text: "Appearance"; font.pixelSize: 19; font.bold: true }
            AppText { text: "Choose a dark theme. Your selection is remembered on this device."; color: root.c.muted }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.c.hover; Layout.topMargin: 5; Layout.bottomMargin: 8 }
            SectionLabel { text: "THEME" }
            GridLayout { Layout.fillWidth: true; columns: width > 500 ? 3 : 2; columnSpacing: 7; rowSpacing: 7
              Repeater { model: backend.themeOptions
                AppButton { required property var modelData; Layout.fillWidth: true; text: "●   " + modelData.name; textColor: modelData.accent; selected: backend.themeName === modelData.name; onClicked: backend.setTheme(modelData.name) }
              }
            }
            RowLayout { AppButton { text: "Choose custom accent"; enabled: backend.themeName === "Custom"; onClicked: backend.chooseCustomAccent() } AppButton { text: "Choose background color"; enabled: backend.themeName === "Custom"; onClicked: backend.chooseCustomBackground() } }
            SectionLabel { text: "WALLPAPER & SURFACES"; Layout.topMargin: 12 }
            RowLayout { AppButton { text: "Choose wallpaper / GIF"; onClicked: backend.chooseWallpaper() } AppButton { text: "Remove wallpaper"; quiet: true; enabled: backend.wallpaperUrl !== ""; onClicked: backend.clearMedia("wallpaper") } }
                AppText { text: "WALLPAPER VISIBILITY  " + Math.round(backend.wallpaperOpacity * 100) + "%"; color: root.alphaColor(root.c.text, .76); font.pixelSize: 11; font.bold: true }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: 0; to: 1; stepSize: .05; value: backend.wallpaperOpacity; onMoved: backend.setOpacity("wallpaper_opacity", value) }
            AppText { text: "PANELS  " + Math.round(backend.panelOpacity * 100) + "%"; color: root.alphaColor(root.c.text, .76); font.pixelSize: 11; font.bold: true }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: .2; to: 1; stepSize: .05; value: backend.panelOpacity; onMoved: backend.setOpacity("panel_opacity", value) }
            AppText { text: "BUTTONS & INPUTS  " + Math.round(backend.controlOpacity * 100) + "%"; color: root.alphaColor(root.c.text, .76); font.pixelSize: 11; font.bold: true }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: .2; to: 1; stepSize: .05; value: backend.controlOpacity; onMoved: backend.setOpacity("control_opacity", value) }
            RowLayout {
                Rectangle { width: 34; height: 34; radius: Math.max(4, root.corner - 4); color: backend.buttonColor; border.width: 1; border.color: root.c.hover }
                AppButton { text: "Choose control tint"; onClicked: backend.chooseButtonColor() }
                AppButton { text: "Use theme default"; quiet: true; onClicked: backend.resetButtonColor() }
            }
            SectionLabel { text: "EDITOR & INTERACTION"; Layout.topMargin: 12 }
            SettingToggle { title: "Interface motion"; description: "Enable short visual transitions and hover feedback."; settingKey: "animations"; checked: backend.animationsEnabled }
            SettingToggle { title: "Enter to send"; description: backend.enterToSend ? "Enter sends; Shift+Enter adds a new line." : "Ctrl+Enter sends; Enter adds a new line."; settingKey: "enter_to_send"; checked: backend.enterToSend }
            SettingToggle { title: "Show Send button"; description: "Display a Send button beside the message editor."; settingKey: "show_send_button"; checked: backend.settings.show_send_button === true }
            SettingToggle { title: "Show formatting buttons"; description: "Display bold, italic, inline code, and code block controls."; settingKey: "show_formatting_buttons"; checked: backend.settings.show_formatting_buttons === true }
            SectionLabel { text: "LAYOUT"; Layout.topMargin: 12 }
            AppText { text: "MESSAGE DENSITY"; color: root.alphaColor(root.c.text, .76); font.pixelSize: 11; font.bold: true }
            RowLayout {
                AppButton { text: "Cozy"; accent: backend.messageDensity === "Cozy"; onClicked: backend.setMessageDensity("Cozy") }
                AppButton { text: "Compact"; accent: backend.messageDensity === "Compact"; onClicked: backend.setMessageDensity("Compact") }
            }
            AppText { text: "TEXT SIZE  " + Math.round(backend.fontScale * 100) + "%"; color: root.alphaColor(root.c.text, .76); font.pixelSize: 11; font.bold: true; Layout.topMargin: 5 }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: .85; to: 1.25; stepSize: .05; value: backend.fontScale; onMoved: backend.setFontScale(value) }
            AppText { text: "CORNER STYLE"; color: root.alphaColor(root.c.text, .76); font.pixelSize: 11; font.bold: true; Layout.topMargin: 5 }
            RowLayout {
                Repeater { model: ["Compact", "Soft", "Rounded"]
                    AppButton { required property string modelData; text: modelData; selected: backend.cornerStyle === modelData; onClicked: backend.setCornerStyle(modelData) }
                }
            }
            AppText { text: "CONVERSATION BACKGROUND"; color: root.alphaColor(root.c.text, .76); font.pixelSize: 11; font.bold: true; Layout.topMargin: 5 }
            RowLayout {
                Rectangle { width: 34; height: 34; radius: Math.max(4, root.corner - 4); color: backend.chatBackground; border.width: 1; border.color: root.c.hover }
                AppButton { text: "Choose color"; onClicked: backend.chooseChatBackground() }
                AppButton { text: "Use theme default"; quiet: true; onClicked: backend.resetChatBackground() }
            }
            AppText { text: "CONVERSATION BACKGROUND OPACITY  " + Math.round(backend.messageBackgroundOpacity * 100) + "%"; color: root.alphaColor(root.c.text, .76); font.pixelSize: 11; font.bold: true }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: .2; to: 1; stepSize: .05; value: backend.messageBackgroundOpacity; onMoved: backend.setOpacity("message_background_opacity", value) }
            Item { Layout.fillHeight: true }
          }
        }
    }

    Component { id: generalSettings; ColumnLayout { spacing: 7
        AppText { text: "General"; font.pixelSize: 19; font.bold: true }
        AppText { text: "Control how Secure Tiles behaves on this device."; color: root.c.muted }
        SectionLabel { text: "STARTUP & UPDATES"; Layout.topMargin: 10 }
        SettingToggle { title: "Check for updates automatically"; description: "Check GitHub Releases after Secure Tiles starts."; settingKey: "auto_check_updates"; checked: backend.settings.auto_check_updates === undefined ? true : backend.settings.auto_check_updates }
        SectionLabel { text: "DISPLAY & SIDEBAR"; Layout.topMargin: 8 }
        SettingToggle { title: "Use 24-hour timestamps"; description: "Show message times in 24-hour format."; settingKey: "use_24_hour_time"; checked: backend.settings.use_24_hour_time === undefined ? true : backend.settings.use_24_hour_time }
        SettingToggle { title: "Remember sidebar state"; description: "Keep the people sidebar collapsed or expanded between sessions."; settingKey: "remember_sidebar"; checked: backend.settings.remember_sidebar === undefined ? true : backend.settings.remember_sidebar }
        Item { Layout.fillHeight: true }
    } }

    component SectionLabel: AppText {
        Layout.fillWidth: true
        color: root.c.accent
        font.pixelSize: Math.round(11 * root.uiScale)
        font.bold: true
        font.letterSpacing: 0.7
    }

    component FieldLabel: AppText {
        Layout.fillWidth: true
        color: root.alphaColor(root.c.text, .82)
        font.pixelSize: Math.round(11 * root.uiScale)
        font.bold: true
        font.letterSpacing: .45
        Layout.topMargin: 3
    }

    component SettingToggle: Rectangle {
        id: setting; property string title; property string description; property string settingKey; property bool checked
        readonly property color stateColor: checked ? "#22c55e" : "#ef4444"
        Layout.fillWidth: true; Layout.maximumWidth: 720; Layout.preferredHeight: 64; radius: Math.max(6, root.corner - 2)
        color: root.alphaColor(settingArea.containsMouse ? Qt.lighter(root.c.tile, 1.08) : root.c.tile, settingArea.containsMouse ? .88 : .72)
        border.width: 1; border.color: settingArea.containsMouse ? root.alphaColor(root.c.accent, .36) : root.alphaColor(root.c.text, .1)
        Behavior on color { ColorAnimation { duration: root.motion } }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                AppText { text: setting.title; font.pixelSize: Math.round(14 * root.uiScale); font.bold: true }
                AppText { Layout.fillWidth: true; text: setting.description; color: root.alphaColor(root.c.text, .76); font.pixelSize: Math.round(12 * root.uiScale); elide: Text.ElideRight }
            }
            AppText { text: setting.checked ? "ON" : "OFF"; color: setting.stateColor; font.pixelSize: Math.round(10 * root.uiScale); font.bold: true }
            Rectangle {
                Layout.preferredWidth: 44; Layout.preferredHeight: 24; radius: 12
                color: setting.stateColor
                Behavior on color { ColorAnimation { duration: root.motion } }
                Rectangle {
                    width: 18; height: 18; radius: 9; y: 3
                    x: setting.checked ? parent.width - width - 3 : 3
                    color: "#ffffff"
                    Behavior on x { NumberAnimation { duration: root.motion; easing.type: Easing.OutCubic } }
                }
            }
        }
        MouseArea { id: settingArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: backend.setPreference(setting.settingKey, !setting.checked) }
    }

    Component { id: privacySettings; ColumnLayout { spacing: 7
        AppText { text: "Privacy"; font.pixelSize: 19; font.bold: true }
        AppText { text: "Private keys remain encrypted locally. The relay handles ciphertext only."; color: root.c.muted }
        SectionLabel { text: "MESSAGE PRIVACY"; Layout.topMargin: 10 }
        SettingToggle { title: "Show decrypted message content"; description: "Hide local conversation text when disabled; encrypted messages remain stored."; settingKey: "message_previews"; checked: backend.settings.message_previews === undefined ? true : backend.settings.message_previews }
        SettingToggle { title: "Send typing indicators"; description: "Let the selected contact see animated dots while you compose a message."; settingKey: "typing_indicators"; checked: backend.settings.typing_indicators === undefined ? true : backend.settings.typing_indicators }
        Item { Layout.fillHeight: true }
    } }
    Component { id: notificationSettings; ColumnLayout { spacing: 7
        AppText { text: "Notifications"; font.pixelSize: 19; font.bold: true }
        AppText { text: "Choose how new messages get your attention."; color: root.c.muted }
        SectionLabel { text: "NEW MESSAGES"; Layout.topMargin: 10 }
        SettingToggle { title: "Message sounds"; description: "Play a sound for new encrypted messages."; settingKey: "message_sounds"; checked: backend.settings.message_sounds === undefined ? true : backend.settings.message_sounds }
        SettingToggle { title: "Desktop notifications"; description: "Show a local notification while in the background."; settingKey: "desktop_notifications"; checked: backend.settings.desktop_notifications === undefined ? true : backend.settings.desktop_notifications }
        Item { Layout.fillHeight: true }
    } }
    Component { id: aboutSettings; ColumnLayout { spacing: 7
        RowLayout {
            Rectangle { width: 52; height: 52; radius: 14; color: root.c.accent; AppText { anchors.centerIn: parent; text: "◆"; color: root.c.bg; font.pixelSize: 18 } }
            ColumnLayout { spacing: 1
                AppText { text: "Secure Tiles"; font.pixelSize: 20; font.bold: true }
                AppText { text: "Version " + backend.appVersion; color: root.c.muted; font.pixelSize: 11 }
            }
        }
        AppText { text: "Private conversations. Keys stay yours."; color: root.c.muted; Layout.topMargin: 4 }
        Panel { Layout.fillWidth: true; Layout.maximumWidth: 720; Layout.preferredHeight: 68; color: root.alphaColor(root.c.tile, backend.panelOpacity)
            ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 3; AppText { text: "RELAY"; color: root.c.muted; font.pixelSize: 9; font.bold: true } AppText { text: backend.relayUrl; elide: Text.ElideMiddle; Layout.fillWidth: true } AppText { text: backend.relayStatus; color: backend.relayStatus === "Relay connected" ? root.c.accent : root.c.danger; font.pixelSize: 11 } }
        }
        Panel { Layout.fillWidth: true; Layout.maximumWidth: 720; Layout.preferredHeight: 62; color: root.alphaColor(root.c.tile, backend.panelOpacity)
            ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 3; AppText { text: "LOCAL DATA"; color: root.c.muted; font.pixelSize: 9; font.bold: true } AppText { text: backend.dataLocation; elide: Text.ElideMiddle; Layout.fillWidth: true } }
        }
        AppText { text: "SECURITY"; color: root.c.muted; font.pixelSize: 9; font.bold: true; Layout.topMargin: 7 }
        AppText { text: "Protocol: secure-tiles-v1\nVault: Argon2id + SecretBox\nMessages: Curve25519 Box + Ed25519 signatures"; color: root.c.muted; lineHeight: 1.35 }
        AppText { text: "UPDATES"; color: root.c.muted; font.pixelSize: 9; font.bold: true; Layout.topMargin: 9 }
        Panel { Layout.fillWidth: true; Layout.maximumWidth: 720; Layout.preferredHeight: 72; color: root.alphaColor(root.c.tile, backend.panelOpacity)
            RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 10
                ColumnLayout { Layout.fillWidth: true; spacing: 3
                    AppText { text: backend.updateReady ? "Version " + backend.updateVersion + " is ready" : "Secure Tiles is kept current through verified GitHub Releases."; font.bold: backend.updateReady }
                    AppText { text: backend.updateStatus || "Updates are checked automatically after startup."; color: backend.updateStatus.indexOf("failed") >= 0 ? root.c.danger : root.c.muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
                AppButton { text: backend.checkingUpdates ? "Checking..." : "Check for updates"; enabled: !backend.checkingUpdates && !backend.updateReady; onClicked: backend.checkForUpdates() }
                AppButton { visible: backend.updateReady; text: "Restart to update"; accent: true; onClicked: backend.restartToUpdate() }
            }
        }
        Item { Layout.fillHeight: true }
    } }
}
