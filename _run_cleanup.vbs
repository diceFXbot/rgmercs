Set shell = CreateObject("WScript.Shell")
repo = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
bat = repo & "\_cleanup_hang.bat"
shell.Run "cmd /c """ & bat & """", 0, False
