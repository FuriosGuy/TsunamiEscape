[CmdletBinding()]
param(
	[string]$UniverseId = "9824719186",
	[string]$ProductId = "3715760243",
	[int]$Price = 19,
	[switch]$Apply
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:ROBLOX_EVENT_API_KEY)) {
	throw "Set ROBLOX_EVENT_API_KEY in the environment before running this script. Do not put the key in this file."
}

$baseUri = "https://apis.roblox.com/developer-products/v2/universes/$UniverseId/developer-products"
$productUri = "$baseUri/$ProductId"
$headers = @{ "x-api-key" = $env:ROBLOX_EVENT_API_KEY }
$client = [System.Net.Http.HttpClient]::new()
$client.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0")
$client.DefaultRequestHeaders.Add("x-api-key", $env:ROBLOX_EVENT_API_KEY)

function Invoke-RobloxRequest {
	param(
		[System.Net.Http.HttpClient]$HttpClient,
		[System.Net.Http.HttpRequestMessage]$Request
	)

	$response = $HttpClient.SendAsync($Request).GetAwaiter().GetResult()
	$body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
	$diagnosticHeaders = @{}
	foreach ($headerName in @("x-roblox-id", "x-request-id", "x-correlation-id", "cf-ray")) {
		$values = [System.Collections.Generic.IEnumerable[string]]$null
		if ($response.Headers.TryGetValues($headerName, [ref]$values)) {
			$diagnosticHeaders[$headerName] = ($values -join ",")
		} elseif ($response.Content.Headers.TryGetValues($headerName, [ref]$values)) {
			$diagnosticHeaders[$headerName] = ($values -join ",")
		}
	}

	[pscustomobject]@{
		StatusCode = [int]$response.StatusCode
		ReasonPhrase = $response.ReasonPhrase
		Body = $body
		DiagnosticHeaders = $diagnosticHeaders
	}
}

try {
	$getRequest = [System.Net.Http.HttpRequestMessage]::new(
		[System.Net.Http.HttpMethod]::Get,
		"$productUri/creator"
	)
	$getResponse = Invoke-RobloxRequest -HttpClient $client -Request $getRequest
	if ($getResponse.StatusCode -lt 200 -or $getResponse.StatusCode -ge 300) {
		throw "Product preflight failed: HTTP $($getResponse.StatusCode) $($getResponse.Body)"
	}

	$product = $getResponse.Body | ConvertFrom-Json
	if ([string]$product.productId -ne $ProductId) {
		throw "Preflight product ID mismatch. Requested $ProductId, received $($product.productId)."
	}
	if ([int64]$product.priceInformation.defaultPriceInRobux -ne $Price) {
		throw "Preflight price mismatch. Expected $Price, received $($product.priceInformation.defaultPriceInRobux)."
	}

	"Product: $($product.name) ($ProductId)"
	"Current state: isForSale=$($product.isForSale), price=$($product.priceInformation.defaultPriceInRobux) Robux"
	"Requested patch: isForSale=true, price=$Price; regional pricing unchanged"

	if (-not $Apply) {
		"Dry run only. Pass -Apply to send one PATCH request."
		return
	}

	$form = [System.Net.Http.MultipartFormDataContent]::new()
	$form.Add([System.Net.Http.StringContent]::new("true"), "isForSale")
	$form.Add([System.Net.Http.StringContent]::new([string]$Price), "price")
	$patchRequest = [System.Net.Http.HttpRequestMessage]::new(
		[System.Net.Http.HttpMethod]::Patch,
		$productUri
	)
	$patchRequest.Content = $form
	$patchResponse = Invoke-RobloxRequest -HttpClient $client -Request $patchRequest

	"PATCH response: HTTP $($patchResponse.StatusCode) $($patchResponse.ReasonPhrase)"
	if ($patchResponse.Body) {
		"Response body: $($patchResponse.Body)"
	}
	if ($patchResponse.DiagnosticHeaders.Count -gt 0) {
		"Diagnostic headers:"
		$patchResponse.DiagnosticHeaders.GetEnumerator() | Sort-Object Key | ForEach-Object {
			"  $($_.Key): $($_.Value)"
		}
	}

	if ($patchResponse.StatusCode -lt 200 -or $patchResponse.StatusCode -ge 300) {
		exit 1
	}

	$verifyRequest = [System.Net.Http.HttpRequestMessage]::new(
		[System.Net.Http.HttpMethod]::Get,
		"$productUri/creator"
	)
	$verifyResponse = Invoke-RobloxRequest -HttpClient $client -Request $verifyRequest
	if ($verifyResponse.StatusCode -lt 200 -or $verifyResponse.StatusCode -ge 300) {
		throw "Post-patch verification failed: HTTP $($verifyResponse.StatusCode) $($verifyResponse.Body)"
	}
	$verifiedProduct = $verifyResponse.Body | ConvertFrom-Json
	"Verified: isForSale=$($verifiedProduct.isForSale), price=$($verifiedProduct.priceInformation.defaultPriceInRobux) Robux"
} finally {
	$client.Dispose()
	$headers = $null
}
