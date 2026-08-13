import QtQuick
import QtQuick.Controls
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

    component Panel: Rectangle {
        color: root.c.panel
        radius: root.corner
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
            radius: Math.max(4, root.corner - 2)
            border.width: control.selected ? 1 : 0
            border.color: root.c.accent
            color: control.down ? root.c.hover : control.hovered ? root.c.hover
                   : control.accent ? root.c.accent : control.quiet ? "transparent" : root.c.tile
            Behavior on color { ColorAnimation { duration: root.motion } }
        }
    }

    component AppField: TextField {
        id: field
        implicitHeight: 42
        color: root.c.text
        placeholderTextColor: root.c.muted
        selectionColor: root.c.accent
        selectedTextColor: root.c.bg
        font.family: "Segoe UI"
        font.pixelSize: Math.round(14 * root.uiScale)
        leftPadding: 13; rightPadding: 13
        background: Rectangle { color: root.c.tile; radius: Math.max(4, root.corner - 2); border.width: field.activeFocus ? 1 : 0; border.color: root.c.accent }
    }

    component Avatar: Rectangle {
        id: avatar
        property int size: 40
        property string initials: backend.displayName.slice(0, 2).toUpperCase()
        width: size; height: size; radius: size / 2; clip: true
        color: root.c.accent
        Image { anchors.fill: parent; source: backend.avatarUrl; fillMode: Image.PreserveAspectCrop; visible: backend.avatarUrl !== ""; cache: false }
        Text { anchors.centerIn: parent; visible: backend.avatarUrl === ""; text: avatar.initials; color: root.c.bg; font.bold: true; font.pixelSize: avatar.size * .34; renderType: Text.NativeRendering }
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
            Panel {
                width: Math.min(440, parent.width - 48)
                height: backend.hasVault ? 410 : 540
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
                        onAccepted: backend.hasVault ? backend.unlock(text, "") : backend.signup(signupName.text, text, relay.text)
                    }
                    AppText { visible: !backend.hasVault; text: "RELAY ADDRESS"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                    AppField { id: relay; visible: !backend.hasVault; Layout.fillWidth: true; placeholderText: "http://127.0.0.1:8765" }
                    AppText { Layout.fillWidth: true; text: backend.status; color: root.c.danger; wrapMode: Text.Wrap; font.pixelSize: 12 }
                    Item { Layout.fillHeight: true }
                    AppButton {
                        Layout.fillWidth: true; accent: true; enabled: !backend.busy
                        text: backend.hasVault ? "Unlock" : backend.busy ? "Creating account..." : "Create secure account"
                        onClicked: backend.hasVault ? backend.unlock(password.text, "") : backend.signup(signupName.text, password.text, relay.text)
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
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 10
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 42
                    AppText { text: "SECURE TILES"; font.pixelSize: 21; font.bold: true }
                    AppText { text: backend.displayName.toUpperCase(); color: root.c.accent; font.pixelSize: 10; font.bold: true }
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
                                AppText { visible: backend.sidebarExpanded; text: "PEOPLE"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
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
                                    required property var modelData
                                    width: ListView.view.width; height: 44
                                    text: backend.sidebarExpanded ? (modelData.favorite ? "★   " : modelData.initials + "   ") + modelData.displayName : (modelData.favorite ? "★" : modelData.initials)
                                    accent: backend.selectedSigningKey === modelData.signing_key
                                    onClicked: backend.selectContact(modelData.signing_key)
                                }
                            }
                            Item { Layout.preferredHeight: 56 }
                        }
                    }
                    Panel {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Loader { anchors.fill: parent; anchors.margins: 14; sourceComponent: backend.page === "settings" ? settingsView : backend.page === "contact" ? contactView : chatView }
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
                                AppText { text: backend.displayName; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
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
                background: Panel { color: root.c.bg; border.width: 1; border.color: root.c.tile }
                contentItem: ColumnLayout {
                    spacing: 0
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 78; color: backend.bannerColor; radius: 12 }
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
                        AppText { text: backend.displayName; font.pixelSize: 17; font.bold: true }
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
                ColumnLayout { spacing: 2; Layout.fillWidth: true
                    AppText { text: backend.selectedName ? backend.selectedDisplayName : "Choose someone to start"; font.pixelSize: 21; font.bold: true }
                    AppText { visible: backend.selectedName !== "" && backend.selectedDisplayName !== backend.selectedName; text: "@" + backend.selectedName; color: root.c.muted; font.pixelSize: 10 }
                    AppText { text: backend.selectedName ? "End-to-end encrypted. Open Profile to verify identity." : "Messages are encrypted before leaving this device."; color: root.c.muted; font.pixelSize: 12 }
                }
                AppField { visible: backend.selectedName !== ""; Layout.preferredWidth: 190; implicitHeight: 36; placeholderText: "Search messages"; onTextChanged: chatRoot.searchQuery = text.toLowerCase() }
                AppButton { text: "Profile"; enabled: backend.selectedName !== ""; ToolTip.visible: hovered; ToolTip.text: "View identity and safety number"; onClicked: backend.openPage("contact") }
            }
            ListView {
                id: history; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: root.compactMessages ? 3 : 9
                model: backend.messages
                Rectangle { parent: history; anchors.fill: parent; color: backend.chatBackground; radius: root.corner; z: -1 }
                onCountChanged: Qt.callLater(positionViewAtEnd)
                header: Item {
                    width: history.width; height: history.count === 0 ? Math.max(180, history.height * .65) : 0
                    ColumnLayout { anchors.centerIn: parent; visible: history.count === 0; spacing: 7
                        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 62; height: 62; radius: 31; color: root.c.tile; AppText { anchors.centerIn: parent; text: backend.selectedName ? backend.selectedDisplayName.slice(0,2).toUpperCase() : "✦"; font.pixelSize: 21; font.bold: true } }
                        AppText { Layout.alignment: Qt.AlignHCenter; text: backend.selectedName ? "Start your conversation with " + backend.selectedDisplayName : "Choose someone from People"; font.pixelSize: 16; font.bold: true }
                        AppText { Layout.alignment: Qt.AlignHCenter; text: backend.selectedName ? "Your first message will be encrypted before it leaves this device." : "Add a username or select the demo account to begin."; color: root.c.muted; font.pixelSize: 11 }
                    }
                }
                delegate: Rectangle {
                    id: messageRow
                    required property var modelData
                    width: ListView.view.width
                    property bool matchesSearch: chatRoot.searchQuery === "" || modelData.plainText.toLowerCase().indexOf(chatRoot.searchQuery) >= 0
                    visible: matchesSearch
                    height: visible ? messageLayout.implicitHeight + (root.compactMessages ? 8 : 16) + (modelData.showDate ? 30 : 0) : 0
                    color: messageHover.containsMouse ? root.c.tile : "transparent"
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
                        Rectangle {
                            visible: !root.compactMessages; Layout.preferredWidth: 38; Layout.preferredHeight: 38; radius: 19
                            color: messageRow.modelData.outgoing ? root.c.accent : root.c.hover
                            AppText { anchors.centerIn: parent; text: messageRow.modelData.outgoing ? backend.displayName.slice(0,2).toUpperCase() : backend.selectedDisplayName.slice(0,2).toUpperCase(); color: messageRow.modelData.outgoing ? root.c.bg : root.c.text; font.bold: true; font.pixelSize: 11 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            RowLayout {
                                Layout.fillWidth: true; spacing: 7
                                AppText { text: messageRow.modelData.sender; color: root.c.accent; font.pixelSize: Math.round(11 * root.uiScale); font.bold: true }
                                AppText { text: messageRow.modelData.timestamp; color: root.c.muted; font.pixelSize: Math.round(10 * root.uiScale); ToolTip.visible: timestampHover.containsMouse; ToolTip.text: messageRow.modelData.fullTimestamp; MouseArea { id: timestampHover; anchors.fill: parent; hoverEnabled: true } }
                                Item { Layout.fillWidth: true }
                            }
                            Text { Layout.fillWidth: true; text: messageRow.modelData.body; textFormat: Text.RichText; color: root.c.text; font.family: "Segoe UI"; font.pixelSize: Math.round(14 * root.uiScale); wrapMode: Text.Wrap; renderType: Text.NativeRendering }
                        }
                        AppButton { visible: messageHover.containsMouse && messageRow.modelData.plainText !== ""; text: "Copy"; quiet: true; Layout.preferredWidth: 54; Layout.preferredHeight: 30; onClicked: backend.copyText(messageRow.modelData.plainText) }
                    }
                    MouseArea { id: messageHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
            Panel {
                Layout.fillWidth: true; Layout.preferredHeight: 116; color: root.c.tile; radius: 10
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 7; spacing: 4
                    RowLayout {
                        spacing: 2
                        AppButton { text: "B"; quiet: true; font.bold: true; Layout.preferredWidth: 38; onClicked: format("**") }
                        AppButton { text: "I"; quiet: true; font.italic: true; Layout.preferredWidth: 38; onClicked: format("*") }
                        AppButton { text: "</>"; quiet: true; Layout.preferredWidth: 44; onClicked: format("`") }
                        AppButton { text: "Code"; quiet: true; Layout.preferredWidth: 52; onClicked: format("```") }
                        AppButton { text: "Clear"; quiet: true; onClicked: composer.text = composer.text.replace(/\*\*|```|`|\*/g, "") }
                        Item { Layout.fillWidth: true }
                        AppText { visible: backend.status !== ""; text: backend.status; color: backend.status.indexOf("WARNING") >= 0 || backend.status.indexOf("Not sent") === 0 ? root.c.danger : root.c.muted; font.pixelSize: 10; elide: Text.ElideRight; Layout.maximumWidth: 280 }
                        AppText { text: composer.length + " / 4000"; color: composer.length > 3800 ? root.c.danger : root.c.muted; font.pixelSize: 10 }
                    }
                    RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 7
                        TextArea {
                            id: composer; Layout.fillWidth: true; Layout.fillHeight: true
                            color: root.c.text; placeholderText: backend.selectedName ? "Message " + backend.selectedDisplayName : "Choose a contact first"; placeholderTextColor: root.c.muted
                            font.family: "Segoe UI"; font.pixelSize: 14; wrapMode: TextEdit.Wrap; padding: 10
                            onTextChanged: { if (length > 4000) remove(4000, length) }
                            background: Rectangle { color: root.c.panel; radius: 8 }
                            Keys.onReturnPressed: function(event) {
                                var shouldSend = backend.enterToSend ? !(event.modifiers & Qt.ShiftModifier) : (event.modifiers & Qt.ControlModifier)
                                if (shouldSend) { backend.sendMessage(text); text = ""; event.accepted = true }
                            }
                        }
                        AppButton { text: "Send"; accent: true; Layout.preferredWidth: 88; Layout.fillHeight: true; enabled: backend.selectedName !== "" && composer.length > 0; onClicked: { backend.sendMessage(composer.text); composer.text = "" } }
                    }
                }
                function format(marker) {
                    var start = composer.selectionStart, end = composer.selectionEnd
                    var selected = composer.text.substring(start, end)
                    var edge = marker === "```" ? "\n" : ""
                    composer.remove(start, end); composer.insert(start, marker + edge + selected + edge + marker); composer.forceActiveFocus()
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
                    Rectangle { width: 82; height: 82; radius: 41; color: root.c.tile; AppText { anchors.centerIn: parent; text: backend.selectedIsDemo ? "BOT" : backend.selectedName.slice(0,2).toUpperCase(); font.pixelSize: 23; font.bold: true } }
                    AppText { text: backend.selectedDisplayName; font.pixelSize: 21; font.bold: true }
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
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                Panel {
                    Layout.preferredWidth: 170; Layout.fillHeight: true; color: root.c.bg
                    ColumnLayout { anchors.fill: parent; anchors.margins: 9; spacing: 4
                        Repeater { model: ["My Profile", "General", "Appearance", "Privacy", "Notifications", "About"]
                            AppButton { required property string modelData; Layout.fillWidth: true; text: modelData; quiet: backend.settingsTab !== modelData; accent: backend.settingsTab === modelData; onClicked: backend.openSettingsTab(modelData) }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
                Panel {
                    Layout.fillWidth: true; Layout.fillHeight: true; color: root.c.bg
                    Loader { anchors.fill: parent; anchors.margins: 24; sourceComponent: backend.settingsTab === "My Profile" ? profileSettings : backend.settingsTab === "General" ? generalSettings : backend.settingsTab === "Appearance" ? appearanceSettings : backend.settingsTab === "Privacy" ? privacySettings : backend.settingsTab === "Notifications" ? notificationSettings : aboutSettings }
                }
            }
        }
    }

    Component {
        id: profileSettings
        Flickable {
            contentHeight: profileColumn.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: profileColumn; width: parent.width; spacing: 9
                AppText { text: "Profile customization"; font.pixelSize: 19; font.bold: true }
                AppText { text: "Your unique username is @" + backend.username + ". It cannot be changed or reused."; color: root.c.muted }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 150; radius: 12; color: root.c.tile; clip: true
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 76; color: backend.bannerColor }
                    Avatar { size: 80; x: 18; y: 42 }
                    AppText { x: 112; y: 91; text: displayName.text || backend.displayName; font.pixelSize: 17; font.bold: true }
                    AppText { x: 112; y: 116; text: "@" + backend.username + (pronouns.text ? "  •  " + pronouns.text : ""); color: root.c.muted; font.pixelSize: 11 }
                }
                RowLayout { AppButton { text: "Change avatar"; onClicked: backend.chooseAvatar() } AppButton { text: "Banner color"; onClicked: backend.chooseBannerColor() } }
                AppText { text: "DISPLAY NAME"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                AppField { id: displayName; Layout.fillWidth: true; text: backend.displayName; placeholderText: "How people see you" }
                AppText { text: "PRONOUNS"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                AppField { id: pronouns; Layout.fillWidth: true; text: backend.pronouns; placeholderText: "Optional pronouns"; maximumLength: 40 }
                AppText { text: "CUSTOM STATUS"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                AppField { id: customStatus; Layout.fillWidth: true; text: backend.customStatus; placeholderText: "What are you up to?" }
                AppText { text: "STATUS EMOJI"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                AppField { id: statusEmoji; Layout.preferredWidth: 150; text: backend.statusEmoji; placeholderText: "e.g. 🎮"; maximumLength: 8 }
                AppText { text: "ABOUT ME"; color: root.c.muted; font.pixelSize: 10; font.bold: true }
                TextArea { id: bio; Layout.fillWidth: true; Layout.preferredHeight: 105; text: backend.bio; color: root.c.text; placeholderText: "Tell people about yourself"; placeholderTextColor: root.c.muted; wrapMode: TextEdit.Wrap; padding: 12; background: Rectangle { color: root.c.tile; radius: 8; border.width: bio.activeFocus ? 1 : 0; border.color: root.c.accent } }
                AppButton { text: "Save profile"; accent: true; onClicked: backend.saveProfile(displayName.text, customStatus.text, bio.text, pronouns.text, backend.bannerColor, statusEmoji.text) }
                AppText { text: backend.status; color: root.c.muted; font.pixelSize: 11 }
            }
        }
    }

    Component {
        id: appearanceSettings
        Flickable {
          contentHeight: appearanceColumn.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
          ColumnLayout { id: appearanceColumn; width: parent.width
            AppText { text: "Appearance"; font.pixelSize: 19; font.bold: true }
            AppText { text: "Choose a dark theme. Your selection is remembered on this device."; color: root.c.muted }
            GridLayout { Layout.fillWidth: true; columns: width > 500 ? 3 : 2; columnSpacing: 7; rowSpacing: 7
              Repeater { model: backend.themeOptions
                AppButton { required property var modelData; Layout.fillWidth: true; text: "●   " + modelData.name; textColor: modelData.accent; selected: backend.themeName === modelData.name; onClicked: backend.setTheme(modelData.name) }
              }
            }
            AppButton { text: "Choose custom accent"; enabled: backend.themeName === "Custom"; onClicked: backend.chooseCustomAccent() }
            SettingToggle { title: "Interface motion"; description: "Enable short visual transitions and hover feedback."; settingKey: "animations"; checked: backend.animationsEnabled }
            SettingToggle { title: "Enter to send"; description: backend.enterToSend ? "Enter sends; Shift+Enter adds a new line." : "Ctrl+Enter sends; Enter adds a new line."; settingKey: "enter_to_send"; checked: backend.enterToSend }
            AppText { text: "MESSAGE DENSITY"; color: root.c.muted; font.pixelSize: 10; font.bold: true; Layout.topMargin: 5 }
            RowLayout {
                AppButton { text: "Cozy"; accent: backend.messageDensity === "Cozy"; onClicked: backend.setMessageDensity("Cozy") }
                AppButton { text: "Compact"; accent: backend.messageDensity === "Compact"; onClicked: backend.setMessageDensity("Compact") }
            }
            AppText { text: "TEXT SIZE  " + Math.round(backend.fontScale * 100) + "%"; color: root.c.muted; font.pixelSize: 10; font.bold: true; Layout.topMargin: 5 }
            Slider { Layout.fillWidth: true; from: .85; to: 1.25; stepSize: .05; value: backend.fontScale; onMoved: backend.setFontScale(value) }
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
            Item { Layout.fillHeight: true }
          }
        }
    }

    Component { id: generalSettings; ColumnLayout {
        AppText { text: "General"; font.pixelSize: 19; font.bold: true }
        AppText { text: "Control how Secure Tiles behaves on this device."; color: root.c.muted }
        SettingToggle { title: "Start local relay automatically"; description: "Start the bundled loopback relay when the app opens."; settingKey: "auto_start_relay"; checked: backend.settings.auto_start_relay === undefined ? true : backend.settings.auto_start_relay }
        SettingToggle { title: "Check for updates automatically"; description: "Check GitHub Releases after Secure Tiles starts."; settingKey: "auto_check_updates"; checked: backend.settings.auto_check_updates === undefined ? true : backend.settings.auto_check_updates }
        SettingToggle { title: "Use 24-hour timestamps"; description: "Show message times in 24-hour format."; settingKey: "use_24_hour_time"; checked: backend.settings.use_24_hour_time === undefined ? true : backend.settings.use_24_hour_time }
        SettingToggle { title: "Remember sidebar state"; description: "Keep the people sidebar collapsed or expanded between sessions."; settingKey: "remember_sidebar"; checked: backend.settings.remember_sidebar === undefined ? true : backend.settings.remember_sidebar }
        Item { Layout.fillHeight: true }
    } }

    component SettingToggle: Rectangle {
        id: setting; property string title; property string description; property string settingKey; property bool checked
        Layout.fillWidth: true; Layout.preferredHeight: 66; radius: 10; color: root.c.tile
        RowLayout { anchors.fill: parent; anchors.margins: 12
            ColumnLayout { Layout.fillWidth: true; spacing: 2; AppText { text: setting.title; font.bold: true } AppText { text: setting.description; color: root.c.muted; font.pixelSize: 11 } }
            Switch { checked: setting.checked; onToggled: backend.setPreference(setting.settingKey, checked) }
        }
    }

    Component { id: privacySettings; ColumnLayout {
        AppText { text: "Privacy"; font.pixelSize: 19; font.bold: true }
        AppText { text: "Private keys remain encrypted locally. The relay handles ciphertext only."; color: root.c.muted }
        SettingToggle { title: "Show decrypted message content"; description: "Hide local conversation text when disabled; encrypted messages remain stored."; settingKey: "message_previews"; checked: backend.settings.message_previews === undefined ? true : backend.settings.message_previews }
        SettingToggle { title: "Send typing indicators"; description: "Reserved for future delivery; no typing metadata is currently sent."; settingKey: "typing_indicators"; checked: backend.settings.typing_indicators === undefined ? false : backend.settings.typing_indicators }
        Item { Layout.fillHeight: true }
    } }
    Component { id: notificationSettings; ColumnLayout {
        AppText { text: "Notifications"; font.pixelSize: 19; font.bold: true }
        SettingToggle { title: "Message sounds"; description: "Play a sound for new encrypted messages."; settingKey: "message_sounds"; checked: backend.settings.message_sounds === undefined ? true : backend.settings.message_sounds }
        SettingToggle { title: "Desktop notifications"; description: "Show a local notification while in the background."; settingKey: "desktop_notifications"; checked: backend.settings.desktop_notifications === undefined ? true : backend.settings.desktop_notifications }
        Item { Layout.fillHeight: true }
    } }
    Component { id: aboutSettings; ColumnLayout {
        RowLayout {
            Rectangle { width: 52; height: 52; radius: 14; color: root.c.accent; AppText { anchors.centerIn: parent; text: "◆"; color: root.c.bg; font.pixelSize: 18 } }
            ColumnLayout { spacing: 1
                AppText { text: "Secure Tiles"; font.pixelSize: 20; font.bold: true }
                AppText { text: "Version " + backend.appVersion; color: root.c.muted; font.pixelSize: 11 }
            }
        }
        AppText { text: "Private conversations. Keys stay yours."; color: root.c.muted; Layout.topMargin: 4 }
        Panel { Layout.fillWidth: true; Layout.preferredHeight: 76; color: root.c.tile
            ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 3; AppText { text: "RELAY"; color: root.c.muted; font.pixelSize: 9; font.bold: true } AppText { text: backend.relayUrl; elide: Text.ElideMiddle; Layout.fillWidth: true } AppText { text: backend.relayStatus; color: backend.relayStatus === "Relay connected" ? root.c.accent : root.c.danger; font.pixelSize: 11 } }
        }
        Panel { Layout.fillWidth: true; Layout.preferredHeight: 70; color: root.c.tile
            ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 3; AppText { text: "LOCAL DATA"; color: root.c.muted; font.pixelSize: 9; font.bold: true } AppText { text: backend.dataLocation; elide: Text.ElideMiddle; Layout.fillWidth: true } }
        }
        AppText { text: "SECURITY"; color: root.c.muted; font.pixelSize: 9; font.bold: true; Layout.topMargin: 7 }
        AppText { text: "Protocol: secure-tiles-v1\nVault: Argon2id + SecretBox\nMessages: Curve25519 Box + Ed25519 signatures"; color: root.c.muted; lineHeight: 1.35 }
        AppText { text: "UPDATES"; color: root.c.muted; font.pixelSize: 9; font.bold: true; Layout.topMargin: 9 }
        Panel { Layout.fillWidth: true; Layout.preferredHeight: 82; color: root.c.tile
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
