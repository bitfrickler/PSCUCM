if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type)
{
$certCallback = @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public class ServerCertificateValidationCallback
    {
        public static void Ignore()
        {
            if(ServicePointManager.ServerCertificateValidationCallback ==null)
            {
                ServicePointManager.ServerCertificateValidationCallback += 
                    delegate
                    (
                        Object obj, 
                        X509Certificate certificate, 
                        X509Chain chain, 
                        SslPolicyErrors errors
                    )
                    {
                        return true;
                    };
            }
        }
    }
"@
    Add-Type $certCallback
 }
 
[ServerCertificateValidationCallback]::Ignore()

function New-CucmObject() {
    param(
        [parameter(Mandatory)][string]$TypeName,
        [parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Properties
    )

    $object = New-Object PSObject

    foreach($key in $Properties.Keys) {
        $object | Add-Member NoteProperty $key $Properties[$key]
    }

    $object
}

function Invoke-CucmApi {
    param(
        [parameter(Mandatory)][string]$Uri,
        [parameter(Mandatory)]$AXL,
        [parameter(Mandatory)]$MethodName,
        [PSCredential]$Credential
    )
    
    # we need to use .NET since Invoke-WebRequest doesn't allow us to specify the HTTP version

    $WebRequest = [System.Net.WebRequest]::Create($Uri) 
    $WebRequest.Method = "POST"
    $WebRequest.ProtocolVersion = [System.Net.HttpVersion]::Version10
    $WebRequest.Headers.Add("SOAPAction","CUCM:DB ver=8.5 $MethodName")
    $WebRequest.ContentType = "text/xml"

    if($Credential -ne $null) {
        $WebRequest.Credentials = $Credential.GetNetworkCredential()
    }

    $Stream = $WebRequest.GetRequestStream()
    $Body = [byte[]][char[]]$AXL
    $Stream.Write($Body, 0, $Body.Length)
    $WebResponse = $WebRequest.GetResponse()
    $WebResponseStream = $WebResponse.GetResponseStream()
    $StreamReader = new-object System.IO.StreamReader $WebResponseStream
    $ResponseData = $StreamReader.ReadToEnd()
    $XmlContent = [xml]$ResponseData
    $XmlContent
}

function Invoke-CucmMethod {
    param(
        [parameter(Mandatory)][string]$Uri,
        [parameter(Mandatory)]$MethodName,
        [parameter(Mandatory=$false)][Hashtable]$Parameters,
        [parameter(Mandatory=$false)][PSCredential]$Credential
    )
    
$axl = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/8.5">
<soapenv:Header/>
<soapenv:Body>
    <ns:$MethodName>
        $(foreach($key in $Parameters.Keys) {
            ("<$key>$($Parameters[$key])</$key>")
        })
    </ns:$MethodName>
</soapenv:Body>
</soapenv:Envelope>
"@

    # We need to use .NET since Invoke-WebRequest doesn't allow us to specify the HTTP version

    $WebRequest = [System.Net.WebRequest]::Create($Uri) 
    $WebRequest.Method = "POST"
    $WebRequest.ProtocolVersion = [System.Net.HttpVersion]::Version10
    $WebRequest.Headers.Add("SOAPAction","CUCM:DB ver=8.5 $MethodName")
    $WebRequest.ContentType = "text/xml"

    if($Credential -ne $null) {
        $WebRequest.Credentials = $Credential.GetNetworkCredential()
    }

    $Stream = $WebRequest.GetRequestStream()
    $Body = [byte[]][char[]]$axl
    $Stream.Write($Body, 0, $Body.Length)

    try {
        $WebResponse = $WebRequest.GetResponse()
        $WebResponseStream = $WebResponse.GetResponseStream()
        $StreamReader = new-object System.IO.StreamReader $WebResponseStream
        $ResponseData = $StreamReader.ReadToEnd()
        $XmlContent = [xml]$ResponseData
        $XmlContent
    }
    catch [System.Net.WebException] {
        #Write-Error "Server returned: $($_.Exception.Response.StatusCode)"
        $null
    }
}

function Invoke-CucmSql {
    param(
        [parameter(Mandatory)][string]$Uri,
        [parameter(Mandatory)][string]$Query,
        [PSCredential]$Credential
    )

$axl = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/8.5">
   <soapenv:Header/>
   <soapenv:Body>
      <ns:executeSQLQuery sequence="?">
         <sql>$Query</sql>
      </ns:executeSQLQuery>
   </soapenv:Body>
</soapenv:Envelope>
"@

    $XmlContent = Invoke-CucmApi -Uri $Uri -AXL $axl -MethodName "executeSQLQuery" -Credential $Credential
    $XmlContent.Envelope.Body.executeSQLQueryResponse.return.row
}

function Get-CucmPhone {
    param(
        [parameter(Mandatory)][string]$Uri,
        [parameter(Mandatory)][string]$Name,
        [PSCredential]$Credential
    )   
    
    $xml = Invoke-CucmMethod -Uri $Uri -MethodName "getPhone" -Credential $Credential -Parameters @{name="$Name"}

    if ($xml -ne $null) {
        $properties = [ordered]@{Name="$($xml.Envelope.Body.getPhoneResponse.return.phone.name)";
            Description="$($xml.Envelope.Body.getPhoneResponse.return.phone.description)";
            Model="$($xml.Envelope.Body.getPhoneResponse.return.phone.model)"}

        $result = New-CucmObject -TypeName "CucmPhone" -Properties $properties
    }

    $result
}