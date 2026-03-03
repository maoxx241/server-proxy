' FRP Client Background Starter

Option Explicit

Dim WshShell, fso, scriptPath, frpcPath, configPath

Set fso = CreateObject("Scripting.FileSystemObject")
scriptPath = fso.GetParentFolderName(WScript.ScriptFullName)
frpcPath = scriptPath & "\frp\frpc.exe"
configPath = scriptPath & "\frpc.toml"

If Not fso.FileExists(frpcPath) Then
    MsgBox "ERROR: frpc.exe not found", vbCritical, "FRP Client"
    WScript.Quit 1
End If

If Not fso.FileExists(configPath) Then
    MsgBox "ERROR: frpc.toml not found", vbCritical, "FRP Client"
    WScript.Quit 1
End If

Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """" & frpcPath & """ -c """ & configPath & """", 0, False

Set WshShell = Nothing
Set fso = Nothing
