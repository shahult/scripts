param(
    [string]$CsvPath = "C:\Temp\subscriptions.csv",
    [switch]$DryRun
)

# CSV format:
# SubscriptionId
# xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

$subs = Import-Csv -Path $CsvPath

foreach ($sub in $subs) {

    $subscriptionId = $sub.SubscriptionId
    Write-Host "`n=== Processing Subscription: $subscriptionId ===" -ForegroundColor Cyan

    Set-AzContext -SubscriptionId $subscriptionId | Out-Null

    # Fetch RGs in Switzerland North
    $rgs = Get-AzResourceGroup | Where-Object { $_.Location -eq "switzerlandnorth" }

    if (-not $rgs) {
        Write-Host "No RGs found in Switzerland North." -ForegroundColor Yellow
        continue
    }

    foreach ($rg in $rgs) {

        $rgName = $rg.ResourceGroupName
        $rgTags = $rg.Tags

        Write-Host "`n--- RG: $rgName (Switzerland North) ---" -ForegroundColor Green

        if (-not $rgTags) {
            Write-Host "RG has no tags. Skipping..." -ForegroundColor Yellow
            continue
        }

        Write-Host "RG Tags:" -ForegroundColor DarkGreen
        $rgTags

        # Get all resources in the RG
        $resources = Get-AzResource -ResourceGroupName $rgName

        foreach ($res in $resources) {

            Write-Host "`nResource: $($res.Name)" -ForegroundColor Magenta

            $oldTags = $res.Tags
            $newTags = @{}

            # Clone existing tags
            if ($oldTags) {
                $newTags = $oldTags.Clone()
            }

            # Merge RG tags (overwrite duplicates)
            foreach ($key in $rgTags.Keys) {
                $newTags[$key] = $rgTags[$key]
            }

            # --- TAG DIFF LOGIC ---
            Write-Host "Tag Diff:" -ForegroundColor Cyan

            # Added or updated tags
            foreach ($key in $rgTags.Keys) {
                if (-not $oldTags.ContainsKey($key)) {
                    Write-Host "  + Added: $key = $($rgTags[$key])" -ForegroundColor Green
                }
                elseif ($oldTags[$key] -ne $rgTags[$key]) {
                    Write-Host "  ~ Updated: $key ($($oldTags[$key]) → $($rgTags[$key]))" -ForegroundColor Yellow
                }
            }

            # No changes?
            if ($newTags.GetEnumerator().Count -eq ($oldTags?.GetEnumerator().Count)) {
                $noChange = $true
                foreach ($key in $newTags.Keys) {
                    if ($oldTags[$key] -ne $newTags[$key]) {
                        $noChange = $false
                        break
                    }
                }

                if ($noChange) {
                    Write-Host "  No tag changes required." -ForegroundColor DarkGray
                    continue
                }
            }

            # --- DRY RUN ---
            if ($DryRun) {
                Write-Host "DRY-RUN: Would apply the following tags:" -ForegroundColor Yellow
                $newTags
                continue
            }

            # --- APPLY TAGS ---
            Write-Host "Applying tags..." -ForegroundColor Green
            Set-AzResource -ResourceId $res.ResourceId -Tag $newTags -Force | Out-Null
        }

        if ($DryRun) {
            Write-Host "`nDRY-RUN: Completed simulated tagging for RG: $rgName" -ForegroundColor Yellow
        }
        else {
            Write-Host "`nCompleted tagging for RG: $rgName" -ForegroundColor Green
        }
    }
}

Write-Host "`nAll done!" -ForegroundColor Cyan
