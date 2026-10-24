' Roda um script PowerShell sem abrir janela e devolve o codigo de saida dele.
' Uso: wscript oculto.vbs "C:\caminho\script.ps1" [argumentos]
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """"
For i = 1 To WScript.Arguments.Count - 1
  cmd = cmd & " " & WScript.Arguments(i)
Next
WScript.Quit sh.Run(cmd, 0, True)
