foreach($line in Get-Content "blaggregator-users.txt") {
    $response = Invoke-WebRequest -Uri "https://blaggregator.recurse.com/profile/$line/" -Headers @{
        "Cache-Control"="max-age=0"
        "sec-ch-ua"="`" Not A;Brand`";v=`"99`", `"Chromium`";v=`"90`", `"Google Chrome`";v=`"90`""
        "sec-ch-ua-mobile"="?0"
        "Upgrade-Insecure-Requests"="1"
        "User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.212 Safari/537.36"
        "Accept"="text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9"
        "Sec-Fetch-Site"="none"
        "Sec-Fetch-Mode"="navigate"
        "Sec-Fetch-User"="?1"
        "Sec-Fetch-Dest"="document"
        "Accept-Encoding"="gzip, deflate, br"
        "Accept-Language"="en-US,en;q=0.9,ru;q=0.8"
        "Cookie"="csrftoken=trT4LCtmtOcnMRFayzAzOdMhN0Em2X3NFkVdGRUpAMOPFPDTxI2aA0zlaldUlBUd; sessionid=cmy0dyxfpn2tsv6czrdz7zsdedgxbgfc"
        }
    $response.Content | Out-File "users\$line.html"
    Write-Output $line
    Start-Sleep 0.5
}