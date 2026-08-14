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
    color: backend.colors.bg

    property var c: backend.colors
    property int motion: backend.animationsEnabled ? 115 : 0
    property real uiScale: backend.fontScale
    property bool compactMessages: backend.messageDensity === "Compact"
    property int corner: backend.cornerRadius
    property color buttonSurface: backend.buttonColor
    property color messageSurface: backend.chatBackground
    function alphaColor(value, amount) { return Qt.rgba(value.r, value.g, value.b, amount) }

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
        border.color: root.alphaColor(Qt.lighter(color, 1.35), 0.16)
    }

    component AppText: Text {
        color: root.c.text
        font.family: "Segoe UI"
        font.pixelSize: Math.round(14 * root.uiScale)
        renderType: Text.NativeRendering
    }

    component AppButton: Button {
        id: control
        property bool accent: false
        property bool quiet: false
        property bool selected: false
        property color textColor: control.accent ? root.c.bg : root.c.text
        implicitHeight: 38
        implicitWidth: Math.max(70, contentItem.implicitWidth + 28)
        hoverEnabled: true
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
            readonly property real surfaceOpacity: backend.controlOpacity * (control.accent || control.selected ? 1 : control.quiet ? (control.hovered || control.down ? .42 : .18) : control.hovered ? .78 : .62)
            readonly property color baseColor: control.hovered || control.down ? Qt.lighter(root.buttonSurface, 1.18) : root.buttonSurface
            radius: Math.max(4, root.corner - 2)
            border.width: quietIdle ? 0 : 1
            border.color: control.selected ? root.c.accent : root.alphaColor(Qt.lighter(baseColor, 1.5), .2)
            color: root.alphaColor(baseColor, surfaceOpacity)
            gradient: Gradient {
                GradientStop { position: 0; color: root.alphaColor(Qt.lighter(buttonBackground.baseColor, 1.12), buttonBackground.surfaceOpacity) }
                GradientStop { position: 1; color: root.alphaColor(Qt.darker(buttonBackground.baseColor, 1.08), buttonBackground.surfaceOpacity) }
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
        font.pixelSize: Math.round(14 * root.uiScale)
        leftPadding: 13; rightPadding: 13
        background: Rectangle {
            color: root.alphaColor(root.buttonSurface, backend.controlOpacity); radius: Math.max(4, root.corner - 2); border.width: 1
            border.color: field.activeFocus ? root.c.accent : root.alphaColor(Qt.lighter(root.buttonSurface, 1.5), .18)
            gradient: Gradient {
                GradientStop { position: 0; color: root.alphaColor(Qt.lighter(root.buttonSurface, 1.08), backend.controlOpacity) }
                GradientStop { position: 1; color: root.alphaColor(Qt.darker(root.buttonSurface, 1.06), backend.controlOpacity) }
            }
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
                anchors.fill: parent; anchors.margins: 12; spacing: 10
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 42
                    AppText { text: "SECURE TILES"; font.pixelSize: 21; font.bold: true }
                    AppText { text: backend.displayName.toUpperCase(); color: root.c.accent; font.family: backend.displayFont; font.pixelSize: 10; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Rectangle { width: 7; height: 7; radius: 4; color: backend.relayStatus === "Relay connected" ? root.c.accent : root.c.danger }
                    AppText { text: backend.relayStatus; color: backend.relayStatus === "Relay connected" ? root.c.accent : root.c.muted; font.pixelSize: 11; font.bold: true }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                    Panel {
                        id: sidebar
                        Layout.fillHeight: true
                        Layout.preferredWidth: backend.sidebarExpanded ? 286 : 72
                        Behavior on Layout.preferredWidth { NumberAnimation { duration: root.motion; easing.type: Easing.OutCubic } }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 9; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                AppButton { visible: backend.sidebarExpanded; text: "People"; quiet: true; Layout.preferredWidth: 76; onClicked: backend.openPage("friends") }
                                Item { Layout.fillWidth: true }
                                AppButton { Layout.preferredWidth: 42; text: backend.sidebarExpanded ? "‹" : "›"; font.pixelSize: 20; ToolTip.visible: hovered; ToolTip.text: backend.sidebarExpanded ? "Collapse people" : "Expand people"; onClicked: backend.toggleSidebar() }
                            }
                            RowLayout {
                                visible: backend.sidebarExpanded; Layout.fillWidth: true; spacing: 6
                                AppField { id: contactSearch; Layout.fillWidth: true; placeholderText: "Add by username"; onAccepted: backend.addContact(text) }
                                AppButton { text: "+"; accent: true; Layout.preferredWidth: 42; ToolTip.visible: hovered; ToolTip.text: "Add by username"; onClicked: backend.addContact(contactSearch.text) }
                            }
                            ListView {
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 5; clip: true
                                model: backend.contacts
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
                                                text: modelData.favorite ? "★" : modelData.initials
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
                                            color: contactButton.textColor; font.pixelSize: 12; font.bold: true
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
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Loader { anchors.fill: parent; anchors.margins: 14; sourceComponent: backend.page === "settings" ? settingsView : backend.page === "contact" ? contactView : backend.page === "friends" ? friendsView : chatView }
                    }
                }
            }

            Panel {
                id: identityBar
                x: 20; y: parent.height - height - 20; width: backend.sidebarExpanded ? 270 : 270; height: 54
                color: root.c.tile; z: 10
                RowLayout {
                    anchors.fill: parent; anchors.margins: 5; spacing: 7
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 8; color: identityArea.containsMouse ? root.c.hover : "transparent"
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 5; spacing: 8
                            Avatar { size: 36 }
                            ColumnLayout { spacing: 0; Layout.fillWidth: true
                                AppText { text: backend.displayName; font.family: backend.displayFont; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                RowLayout { spacing: 5; Rectangle { width: 7; height: 7; radius: 4; color: backend.presenceColor } AppText { text: backend.presence; font.pixelSize: 10 } }
                            }
                        }
                        MouseArea { id: identityArea; anchors.fill: parent; hoverEnabled: true; onClicked: profilePopup.open() }
                    }
                    AppButton { Layout.preferredWidth: 42; text: "⚙"; font.pixelSize: 17; ToolTip.visible: hovered; ToolTip.text: "User Settings"; onClicked: backend.openSettingsTab("My Profile") }
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
                    AppText { text: backend.selectedName ? "End-to-end encrypted. Open Profile to verify identity." : "Messages are encrypted before leaving this device."; color: root.c.muted; font.pixelSize: 12 }
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
                    color: "transparent"
                    radius: 7
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
                                    text: messageRow.modelData.sender; color: senderProfileArea.containsMouse ? root.c.text : root.c.accent; font.family: messageRow.modelData.senderFont; font.pixelSize: Math.round(11 * root.uiScale); font.bold: true; font.underline: senderProfileArea.containsMouse
                                    Behavior on color { ColorAnimation { duration: root.motion } }
                                    MouseArea { id: senderProfileArea; anchors.fill: parent; enabled: !messageRow.modelData.outgoing; hoverEnabled: true; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: backend.openPage("contact") }
                                }
                                AppText { text: messageRow.modelData.timestamp; color: root.c.muted; font.pixelSize: Math.round(10 * root.uiScale); ToolTip.visible: timestampHover.containsMouse; ToolTip.text: messageRow.modelData.fullTimestamp; MouseArea { id: timestampHover; anchors.fill: parent; hoverEnabled: true } }
                                Item { Layout.fillWidth: true }
                            }
                            Text { Layout.fillWidth: true; text: messageRow.modelData.body; textFormat: Text.RichText; color: root.c.text; font.family: "Segoe UI"; font.pixelSize: Math.round(14 * root.uiScale); wrapMode: Text.Wrap; renderType: Text.NativeRendering }
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
                Layout.fillWidth: true; Layout.preferredHeight: backend.pendingAttachments.length > 0 ? 154 : 116; color: root.alphaColor(root.buttonSurface, backend.controlOpacity); radius: 10
                border.width: 1; border.color: root.alphaColor(Qt.lighter(root.buttonSurface, 1.5), .18)
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
                            font.family: "Segoe UI"; font.pixelSize: 14; wrapMode: TextEdit.Wrap; padding: 10
                            onTextChanged: {
                                if (length > 4000) remove(4000, length)
                                backend.setTyping(length > 0 && activeFocus)
                            }
                            onActiveFocusChanged: backend.setTyping(length > 0 && activeFocus)
                            background: Rectangle { color: "transparent"; radius: 8; border.width: editor.activeFocus ? 1 : 0; border.color: root.c.accent }
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
                model: backend.contacts
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
                Layout.fillWidth: true; Layout.preferredHeight: 390; color: root.c.bg
                ColumnLayout { anchors.fill: parent; anchors.margins: 26; spacing: 8
                    Rectangle { width: 82; height: 82; radius: 41; color: root.c.tile; AppText { anchors.centerIn: parent; text: backend.selectedIsDemo ? "BOT" : backend.selectedName.slice(0,2).toUpperCase(); font.pixelSize: 23; font.bold: true } StatusBadge { status: backend.selectedPresence; size: 22; anchors.right: parent.right; anchors.bottom: parent.bottom } }
                    AppText { text: backend.selectedDisplayName; font.family: backend.selectedDisplayFont; font.pixelSize: 21; font.bold: true }
                    AppText { text: "@" + backend.selectedName; color: root.c.muted }
                    AppText { text: backend.selectedIsDemo ? "Demo encrypted echo account" : "Secure Tiles contact"; color: root.c.muted }
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
            spacing: 12
            RowLayout { Layout.fillWidth: true; AppText { text: "Settings"; font.pixelSize: 23; font.bold: true } Item { Layout.fillWidth: true } AppButton { text: "Back to messages"; onClicked: backend.openPage("chat") } }
            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 16
                Panel {
                    Layout.preferredWidth: 170; Layout.fillHeight: true; color: "transparent"; radius: 0
                    ColumnLayout { anchors.fill: parent; anchors.margins: 9; spacing: 4
                        Repeater { model: ["My Profile", "General", "Appearance", "Privacy", "Notifications", "About"]
                            Item {
                                required property string modelData
                                Layout.fillWidth: true; Layout.preferredHeight: 38
                                Rectangle { visible: backend.settingsTab === parent.modelData; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 22; radius: 2; color: root.c.accent }
                                AppButton { anchors.fill: parent; anchors.leftMargin: 7; text: parent.modelData; quiet: true; textColor: backend.settingsTab === parent.modelData ? root.c.accent : root.c.text; onClicked: backend.openSettingsTab(parent.modelData) }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: root.c.hover; opacity: 0.75 }
                Panel {
                    Layout.fillWidth: true; Layout.fillHeight: true; color: "transparent"; radius: 0
                    Loader { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 12; anchors.topMargin: 18; anchors.bottomMargin: 18; sourceComponent: backend.settingsTab === "My Profile" ? profileSettings : backend.settingsTab === "General" ? generalSettings : backend.settingsTab === "Appearance" ? appearanceSettings : backend.settingsTab === "Privacy" ? privacySettings : backend.settingsTab === "Notifications" ? notificationSettings : aboutSettings }
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
                AppText { text: "DISPLAY NAME"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                AppField { id: displayName; Layout.fillWidth: true; text: backend.displayName; placeholderText: "How people see you" }
                AppText { text: "DISPLAY NAME FONT"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                ComboBox {
                    id: displayFont; Layout.preferredWidth: 220; model: backend.displayFontOptions
                    textRole: "name"; valueRole: "family"; font.family: currentValue || backend.displayFont
                    Component.onCompleted: { for (var i = 0; i < count; ++i) if (valueAt(i) === backend.displayFont) { currentIndex = i; break } }
                    onActivated: backend.setDisplayFont(currentValue)
                    implicitHeight: 38; leftPadding: 12; rightPadding: 34
                    contentItem: AppText { text: displayFont.displayText; font.family: displayFont.currentValue || backend.displayFont; verticalAlignment: Text.AlignVCenter }
                    indicator: AppText { x: displayFont.width - width - 12; anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: root.c.muted; font.pixelSize: 16 }
                    background: Rectangle {
                        radius: Math.max(4, root.corner - 2); color: root.alphaColor(root.buttonSurface, backend.controlOpacity)
                        border.width: 1; border.color: displayFont.activeFocus ? root.c.accent : root.alphaColor(Qt.lighter(root.buttonSurface, 1.5), .18)
                    }
                }
                AppText { text: "PRONOUNS"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                AppField { id: pronouns; Layout.fillWidth: true; text: backend.pronouns; placeholderText: "Optional pronouns"; maximumLength: 40 }
                AppText { text: "CUSTOM STATUS"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                AppField { id: customStatus; Layout.fillWidth: true; text: backend.customStatus; placeholderText: "What are you up to?" }
                AppText { text: "STATUS EMOJI"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                AppField { id: statusEmoji; Layout.preferredWidth: 150; text: backend.statusEmoji; placeholderText: "e.g. 🎮"; maximumLength: 8 }
                AppText { text: "ABOUT ME"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                TextArea { id: bio; Layout.fillWidth: true; Layout.preferredHeight: 92; text: backend.bio; color: root.c.text; placeholderText: "Tell people about yourself"; placeholderTextColor: root.c.muted; wrapMode: TextEdit.Wrap; padding: 11; background: Rectangle { color: root.alphaColor(root.buttonSurface, backend.controlOpacity); radius: Math.max(4, root.corner - 2); border.width: 1; border.color: bio.activeFocus ? root.c.accent : root.alphaColor(Qt.lighter(root.buttonSurface, 1.5), .18) } }
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
            AppText { text: "WALLPAPER VISIBILITY  " + Math.round(backend.wallpaperOpacity * 100) + "%"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: 0; to: 1; stepSize: .05; value: backend.wallpaperOpacity; onMoved: backend.setOpacity("wallpaper_opacity", value) }
            AppText { text: "PANELS  " + Math.round(backend.panelOpacity * 100) + "%"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: .2; to: 1; stepSize: .05; value: backend.panelOpacity; onMoved: backend.setOpacity("panel_opacity", value) }
            AppText { text: "BUTTONS & INPUTS  " + Math.round(backend.controlOpacity * 100) + "%"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: .2; to: 1; stepSize: .05; value: backend.controlOpacity; onMoved: backend.setOpacity("control_opacity", value) }
            RowLayout {
                Rectangle { width: 34; height: 34; radius: Math.max(4, root.corner - 4); color: backend.buttonColor; border.width: 1; border.color: root.c.hover }
                AppButton { text: "Choose buttons & inputs color"; onClicked: backend.chooseButtonColor() }
                AppButton { text: "Use theme default"; quiet: true; onClicked: backend.resetButtonColor() }
            }
            SectionLabel { text: "EDITOR & INTERACTION"; Layout.topMargin: 12 }
            SettingToggle { title: "Interface motion"; description: "Enable short visual transitions and hover feedback."; settingKey: "animations"; checked: backend.animationsEnabled }
            SettingToggle { title: "Enter to send"; description: backend.enterToSend ? "Enter sends; Shift+Enter adds a new line." : "Ctrl+Enter sends; Enter adds a new line."; settingKey: "enter_to_send"; checked: backend.enterToSend }
            SettingToggle { title: "Show Send button"; description: "Display a Send button beside the message editor."; settingKey: "show_send_button"; checked: backend.settings.show_send_button === true }
            SettingToggle { title: "Show formatting buttons"; description: "Display bold, italic, inline code, and code block controls."; settingKey: "show_formatting_buttons"; checked: backend.settings.show_formatting_buttons === true }
            SectionLabel { text: "LAYOUT"; Layout.topMargin: 12 }
            AppText { text: "MESSAGE DENSITY"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
            RowLayout {
                AppButton { text: "Cozy"; accent: backend.messageDensity === "Cozy"; onClicked: backend.setMessageDensity("Cozy") }
                AppButton { text: "Compact"; accent: backend.messageDensity === "Compact"; onClicked: backend.setMessageDensity("Compact") }
            }
            AppText { text: "TEXT SIZE  " + Math.round(backend.fontScale * 100) + "%"; color: root.c.muted; font.pixelSize: 10; font.bold: true; Layout.topMargin: 5 }
            Slider { Layout.preferredWidth: Math.min(420, appearanceColumn.width); from: .85; to: 1.25; stepSize: .05; value: backend.fontScale; onMoved: backend.setFontScale(value) }
            AppText { text: "CORNER STYLE"; color: root.c.muted; font.pixelSize: 10; font.bold: true; Layout.topMargin: 5 }
            RowLayout {
                Repeater { model: ["Compact", "Soft", "Rounded"]
                    AppButton { required property string modelData; text: modelData; selected: backend.cornerStyle === modelData; onClicked: backend.setCornerStyle(modelData) }
                }
            }
            AppText { text: "CONVERSATION BACKGROUND"; color: root.c.muted; font.pixelSize: 10; font.bold: true; Layout.topMargin: 5 }
            RowLayout {
                Rectangle { width: 34; height: 34; radius: Math.max(4, root.corner - 4); color: backend.chatBackground; border.width: 1; border.color: root.c.hover }
                AppButton { text: "Choose color"; onClicked: backend.chooseChatBackground() }
                AppButton { text: "Use theme default"; quiet: true; onClicked: backend.resetChatBackground() }
            }
            AppText { text: "CONVERSATION BACKGROUND OPACITY  " + Math.round(backend.messageBackgroundOpacity * 100) + "%"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
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
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 0.7
    }

    component SettingToggle: Rectangle {
        id: setting; property string title; property string description; property string settingKey; property bool checked
        readonly property color stateColor: checked ? "#22c55e" : "#ef4444"
        Layout.fillWidth: true; Layout.maximumWidth: 720; Layout.preferredHeight: 56; radius: Math.max(6, root.corner - 2)
        color: settingArea.containsMouse ? root.c.tile : "transparent"
        Behavior on color { ColorAnimation { duration: root.motion } }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 12
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                AppText { text: setting.title; font.pixelSize: 13; font.bold: true }
                AppText { Layout.fillWidth: true; text: setting.description; color: root.c.muted; font.pixelSize: 10; elide: Text.ElideRight }
            }
            AppText { text: setting.checked ? "ON" : "OFF"; color: setting.stateColor; font.pixelSize: 9; font.bold: true }
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
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: root.c.hover; opacity: 0.7 }
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
