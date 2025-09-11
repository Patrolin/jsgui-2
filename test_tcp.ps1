$client = New-Object System.Net.Sockets.TcpClient("localhost", 3000)
$stream = $client.GetStream()
$writer = New-Object System.IO.StreamWriter($stream)
$writer.AutoFlush = $true
$writer.Write("Hello server!")
$writer.Close()
$client.Close()
