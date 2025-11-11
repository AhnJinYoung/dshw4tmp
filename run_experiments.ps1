<# 
    Experiment automation for SortingTest.java.
    Generates datasets under multiple distributions, runs sorting algorithms,
    and gathers statistics until confidence targets are met.
#>

[CmdletBinding()]
param(
    [int]$ArraySize = 4000,
    [int]$MinSamples = 8,
    [int]$MaxSamples = 40,
    [double]$MaxHalfWidthMs = 0.5,
    [double]$MaxHalfWidthRelative = 0.05,
    [double]$Confidence = 0.95,
    [string]$JavaCommand = "java",
    [string]$JavaClass = "SortingTest",
    [string[]]$Algorithms = @('I','Q','M','H','R'),
    [int[]]$DigitKs = @(1,2,3,4,5,6,7,8,9),
    [double[]]$DuplicateRatios = @(0.5,0.75,0.9,0.99),
    [double[]]$SortedRatios = @(0.0,0.25,0.5,0.75,0.9,0.99),
    [double]$DuplicateTolerance = 0.02,
    [double]$SortedTolerance = 0.02,
    [int]$RandomSeed = 12345
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-InverseStandardNormal {
    param([double]$Probability)

    if ($Probability -le 0.0 -or $Probability -ge 1.0) {
        throw "Probability for inverse normal must be in (0, 1)."
    }

    $a = @(
        -39.6968302866538,
         220.946098424521,
        -275.928510446969,
         138.357751867269,
         -30.6647980661472,
           2.50662827745924
    )

    $b = @(
        -54.4760987982241,
         161.585836858041,
        -155.698979859887,
          66.8013118877197,
         -13.2806815528857
    )

    $c = @(
        -0.00778489400243029,
        -0.322396458041137,
        -2.40075827716184,
        -2.54973253934373,
         4.37466414146497,
         2.93816398269878
    )

    $d = @(
         0.00778469570904146,
         0.32246712907004,
         2.44513413714299,
         3.75440866190742
    )

    $plow = 0.02425
    $phigh = 1.0 - $plow

    if ($Probability -lt $plow) {
        $q = [Math]::Sqrt(-2.0 * [Math]::Log($Probability))
        return ((((( $c[0] * $q + $c[1]) * $q + $c[2]) * $q + $c[3]) * $q + $c[4]) * $q + $c[5]) /
               (((( $d[0] * $q + $d[1]) * $q + $d[2]) * $q + $d[3]) * $q + 1.0)
    }

    if ($phigh -lt $Probability) {
        $q = [Math]::Sqrt(-2.0 * [Math]::Log(1.0 - $Probability))
        return -((((( $c[0] * $q + $c[1]) * $q + $c[2]) * $q + $c[3]) * $q + $c[4]) * $q + $c[5]) /
                (((( $d[0] * $q + $d[1]) * $q + $d[2]) * $q + $d[3]) * $q + 1.0)
    }

    $q = $Probability - 0.5
    $r = $q * $q
    ((((( $a[0] * $r + $a[1]) * $r + $a[2]) * $r + $a[3]) * $r + $a[4]) * $r + $a[5]) * $q /
    ((((( $b[0] * $r + $b[1]) * $r + $b[2]) * $r + $b[3]) * $r + $b[4]) * $r + 1.0)
}

function Get-ConfidenceZ([double]$c) {
    if ($c -lt 0.5 -or $c -ge 1.0) {
        throw "Confidence must be in [0.5, 1.0)."
    }
    $prob = (1.0 + $c) / 2.0
    Get-InverseStandardNormal -Probability $prob
}

function New-StatState {
    [PSCustomObject]@{
        Count = 0
        Mean = 0.0
        M2 = 0.0
    }
}

function Add-Sample {
    param(
        [PSCustomObject]$State,
        [double]$Value
    )
    $State.Count++
    $delta = $Value - $State.Mean
    $State.Mean += $delta / $State.Count
    $delta2 = $Value - $State.Mean
    $State.M2 += $delta * $delta2
}

function Get-Std {
    param([PSCustomObject]$State)
    if ($State.Count -lt 2) { return [double]::NaN }
    [Math]::Sqrt($State.M2 / ($State.Count - 1))
}

function Get-HalfWidth {
    param(
        [PSCustomObject]$State,
        [double]$Z
    )
    $std = Get-Std -State $State
    if ([double]::IsNaN($std)) { return [double]::NaN }
    if ($State.Count -lt 1) { return [double]::NaN }
    $Z * $std / [Math]::Sqrt([double]$State.Count)
}

function Has-SufficientPower {
    param(
        [PSCustomObject]$State,
        [double]$Z,
        [int]$MinSamples,
        [double]$MaxHalfWidthMs,
        [double]$MaxHalfWidthRelative
    )
    if ($State.Count -lt $MinSamples) { return $false }
    $halfWidth = Get-HalfWidth -State $State -Z $Z
    if ([double]::IsNaN($halfWidth)) { return $false }
    if ($halfWidth -le $MaxHalfWidthMs) { return $true }
    if ([Math]::Abs($State.Mean) -le [double]::Epsilon) { return $false }
    ($halfWidth / [Math]::Abs($State.Mean)) -le $MaxHalfWidthRelative
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path)
    }
}

function Get-CollisionRatio {
    param([int[]]$Values)
    if (-not $Values) { return 0.0 }
    $freq = New-Object 'System.Collections.Generic.Dictionary[int,int]'
    $duplicates = 0
    foreach ($v in $Values) {
        if ($freq.ContainsKey($v)) {
            $freq[$v] += 1
            $duplicates++
        } else {
            $freq[$v] = 1
        }
    }
    $duplicates / [double]$Values.Length
}

function Get-SortedRatio {
    param([int[]]$Values)
    $n = $Values.Length
    if ($n -le 1) { return 1.0 }
    $count = 0
    for ($i = 0; $i -lt $n - 1; $i++) {
        if ($Values[$i] -le $Values[$i + 1]) { $count++ }
    }
    $count / [double]$n
}

function Generate-DigitsSample {
    param(
        [int]$Size,
        [int]$Digits,
        [System.Random]$Random
    )
    $maxBound = [Math]::Pow(10, $Digits) - 1
    if ($maxBound -gt [int]::MaxValue) { $maxBound = [int]::MaxValue }
    if ($maxBound -lt 1) { $maxBound = 1 }
    $maxInt = [Convert]::ToInt32([Math]::Floor($maxBound))

    $values = New-Object int[] $Size
    for ($i = 0; $i -lt $Size; $i++) {
        $values[$i] = $Random.Next(-$maxInt, $maxInt + 1)
    }

    $actualDigits = 0
    foreach ($v in $values) {
        $candidate = $v
        if ($candidate -eq [int]::MinValue) { $candidate = [int]::MaxValue }
        if ($candidate -lt 0) { $candidate = -$candidate }
        $digits = 1
        while ($candidate -ge 10) {
            $candidate = [int]($candidate / 10)
            $digits++
        }
        if ($digits -gt $actualDigits) { $actualDigits = $digits }
    }

    [PSCustomObject]@{
        Values = $values
        Actual = $actualDigits
    }
}

function Generate-DuplicateSample {
    param(
        [int]$Size,
        [double]$TargetRatio,
        [double]$Tolerance,
        [System.Random]$Random,
        [int]$MaxAttempts = 30
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $dupTarget = [Math]::Round($TargetRatio * $Size)
        if ($dupTarget -ge $Size) { $dupTarget = $Size - 1 }
        if ($dupTarget -lt 0) { $dupTarget = 0 }
        $uniqueCount = [Math]::Max(1, $Size - [int]$dupTarget)

        $uniqueSet = New-Object 'System.Collections.Generic.HashSet[int]'
        while ($uniqueSet.Count -lt $uniqueCount) {
            [void]$uniqueSet.Add($Random.Next(-1000000, 1000001))
        }
        $uniqueArray = $uniqueSet.ToArray()

        $values = New-Object int[] $Size
        for ($i = 0; $i -lt $uniqueCount; $i++) {
            $values[$i] = $uniqueArray[$i]
        }
        for ($i = $uniqueCount; $i -lt $Size; $i++) {
            $values[$i] = $uniqueArray[$Random.Next(0, $uniqueCount)]
        }

        for ($i = $Size - 1; $i -gt 0; $i--) {
            $j = $Random.Next(0, $i + 1)
            $tmp = $values[$i]
            $values[$i] = $values[$j]
            $values[$j] = $tmp
        }

        $actual = Get-CollisionRatio -Values $values
        if ([Math]::Abs($actual - $TargetRatio) -le $Tolerance) {
            return [PSCustomObject]@{
                Values = $values
                Actual = $actual
            }
        }
    }

    throw "Unable to generate duplicate sample reaching ratio $TargetRatio within tolerance $Tolerance."
}

function Generate-SortedSample {
    param(
        [int]$Size,
        [double]$TargetRatio,
        [double]$Tolerance,
        [System.Random]$Random,
        [int]$MaxAttempts = 30
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $values = New-Object int[] $Size
        $values[0] = $Random.Next(-500000, 500001)
        for ($i = 0; $i -lt $Size - 1; $i++) {
            if ($Random.NextDouble() -le $TargetRatio) {
                $inc = $Random.Next(0, 301)
                $values[$i + 1] = $values[$i] + $inc
            } else {
                $dec = $Random.Next(1, 301)
                $values[$i + 1] = $values[$i] - $dec
            }
        }

        $actual = Get-SortedRatio -Values $values
        if ([Math]::Abs($actual - $TargetRatio) -le $Tolerance) {
            return [PSCustomObject]@{
                Values = $values
                Actual = $actual
            }
        }
    }

    throw "Unable to generate sortedness sample reaching ratio $TargetRatio within tolerance $Tolerance."
}

function Invoke-SortingTest {
    param(
        [int[]]$Values,
        [char]$Algorithm,
        [string]$JavaCommand,
        [string]$JavaClass,
        [string]$WorkingDirectory
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $JavaCommand
    $psi.Arguments = $JavaClass
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    $nullHandler = { }
    $process.add_OutputDataReceived($nullHandler)
    $process.add_ErrorDataReceived($nullHandler)

    if (-not $process.Start()) {
        throw "Failed to start $JavaCommand $JavaClass."
    }

    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    $writer = $process.StandardInput
    $writer.WriteLine($Values.Length)
    foreach ($value in $Values) {
        $writer.WriteLine($value)
    }
    $writer.Flush()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $writer.WriteLine($Algorithm)
    $writer.WriteLine('X')
    $writer.Flush()
    $writer.Close()

    $process.WaitForExit()
    $stopwatch.Stop()

    if ($process.ExitCode -ne 0) {
        throw "SortingTest exited with code $($process.ExitCode)."
    }

    $stopwatch.Elapsed.TotalMilliseconds
}

function Run-Scenario {
    param(
        [string]$Scenario,
        [object[]]$Parameters,
        [ScriptBlock]$Generator,
        [System.Random]$Random,
        [hashtable]$Config,
        [string[]]$Algorithms,
        [string]$JavaCommand,
        [string]$JavaClass,
        [string]$WorkDir
    )

    $records = New-Object 'System.Collections.Generic.List[object]'

    foreach ($paramValue in $Parameters) {
        Write-Host "Running scenario '$Scenario' with parameter $paramValue..."

        $states = @{}
        $actuals = @{}
        foreach ($algo in $Algorithms) {
            $states[$algo] = New-StatState
            $actuals[$algo] = New-StatState
        }

        $powerSatisfied = $false
        for ($rep = 1; $rep -le $Config.MaxSamples; $rep++) {
            $sample = & $Generator.Invoke($paramValue, $Random)
            $values = [int[]]$sample.Values
            $actual = [double]$sample.Actual

            foreach ($algo in $Algorithms) {
                $elapsed = Invoke-SortingTest -Values $values -Algorithm $algo -JavaCommand $JavaCommand -JavaClass $JavaClass -WorkingDirectory $WorkDir
                Add-Sample -State $states[$algo] -Value $elapsed
                Add-Sample -State $actuals[$algo] -Value $actual
            }

            $allSatisfied = $true
            foreach ($algo in $Algorithms) {
                if (-not (Has-SufficientPower -State $states[$algo] -Z $Config.Z -MinSamples $Config.MinSamples -MaxHalfWidthMs $Config.MaxHalfWidthMs -MaxHalfWidthRelative $Config.MaxHalfWidthRelative)) {
                    $allSatisfied = $false
                    break
                }
            }

            if ($allSatisfied) {
                Write-Host "  Achieved target power after $rep replicates."
                $powerSatisfied = $true
                break
            }
        }

        foreach ($algo in $Algorithms) {
            $state = $states[$algo]
            $std = Get-Std -State $state
            $halfWidth = Get-HalfWidth -State $state -Z $Config.Z
            $records.Add([PSCustomObject]@{
                Scenario = $Scenario
                Parameter = $paramValue
                Algorithm = $algo
                Samples = $state.Count
                MeanMs = [Math]::Round($state.Mean, 6)
                StdMs = if ([double]::IsNaN($std)) { [double]::NaN } else { [Math]::Round($std, 6) }
                HalfWidthMs = if ([double]::IsNaN($halfWidth)) { [double]::NaN } else { [Math]::Round($halfWidth, 6) }
                PowerSatisfied = (Has-SufficientPower -State $state -Z $Config.Z -MinSamples $Config.MinSamples -MaxHalfWidthMs $Config.MaxHalfWidthMs -MaxHalfWidthRelative $Config.MaxHalfWidthRelative)
                ActualParameterMean = [Math]::Round($actuals[$algo].Mean, 6)
            })
        }

        if (-not $powerSatisfied) {
            Write-Warning "Scenario '$Scenario' parameter $paramValue reached max samples without hitting all confidence targets."
        }
    }

    return $records
}

function Compute-Recommendations {
    param(
        [System.Collections.Generic.List[object]]$Records,
        [hashtable]$Info
    )

    $recommendations = [ordered]@{}

    $digits = $Records | Where-Object { $_.Scenario -eq 'digits' }
    if ($digits) {
        $bestByK = $digits | Group-Object Parameter | ForEach-Object {
            $best = $_.Group | Sort-Object MeanMs | Select-Object -First 1
            $parsed = [int]::Parse($_.Name.ToString(), [System.Globalization.CultureInfo]::InvariantCulture)
            [PSCustomObject]@{
                Parameter = $parsed
                Algorithm = $best.Algorithm
                MeanMs = $best.MeanMs
            }
        } | Sort-Object Parameter

        $radixDominant = $bestByK | Where-Object { $_.Algorithm -eq 'R' }
        if ($radixDominant) {
            $recommendations.k_digits = ($radixDominant | Select-Object -Last 1).Parameter
        } else {
            $recommendations.k_digits = $DigitKs[0] - 1
        }
        $recommendations.digits_summary = $bestByK
    }

    $dup = $Records | Where-Object { $_.Scenario -eq 'duplicates' }
    if ($dup) {
        $bestDup = $dup | Group-Object Parameter | ForEach-Object {
            $paramValue = [double]::Parse($_.Name.ToString(), [System.Globalization.CultureInfo]::InvariantCulture)
            $best = $_.Group | Sort-Object MeanMs | Select-Object -First 1
            [PSCustomObject]@{
                Parameter = $paramValue
                Algorithm = $best.Algorithm
                MeanMs = $best.MeanMs
            }
        } | Sort-Object Parameter

        $insertionRange = $bestDup | Where-Object { $_.Algorithm -eq 'I' }
        if ($insertionRange) {
            $recommendations.k_collision = ($insertionRange | Select-Object -First 1).Parameter
        } else {
            $recommendations.k_collision = [double]1.1
        }
        $recommendations.duplicates_summary = $bestDup
    }

    $sorted = $Records | Where-Object { $_.Scenario -eq 'sortedness' }
    if ($sorted) {
        $bestSorted = $sorted | Group-Object Parameter | ForEach-Object {
            $paramValue = [double]::Parse($_.Name.ToString(), [System.Globalization.CultureInfo]::InvariantCulture)
            $best = $_.Group | Sort-Object MeanMs | Select-Object -First 1
            [PSCustomObject]@{
                Parameter = $paramValue
                Algorithm = $best.Algorithm
                MeanMs = $best.MeanMs
            }
        } | Sort-Object Parameter

        $insertionSorted = $bestSorted | Where-Object { $_.Algorithm -eq 'I' }
        if ($insertionSorted) {
            $recommendations.k_sorted = ($insertionSorted | Select-Object -First 1).Parameter
        } else {
            $recommendations.k_sorted = [double]1.1
        }
        $recommendations.sorted_summary = $bestSorted
    }

    $recommendations.default_algorithm = 'Q'
    $recommendations
}

function Write-RecommendationSummary {
    param(
        $Recommendations,
        [string]$OutputPath
    )

    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine("Experiment Summary") | Out-Null
    $sb.AppendLine("-------------------") | Out-Null

    if ($Recommendations.Contains("k_digits")) {
        $sb.AppendLine("Digits experiment: recommend radix sort when max digits <= $($Recommendations.k_digits).") | Out-Null
        $sb.AppendLine("Per-digit winners:") | Out-Null
        foreach ($row in $Recommendations.digits_summary) {
            $sb.AppendLine(("  k={0}: {1} ({2} ms)" -f $row.Parameter, $row.Algorithm, $row.MeanMs)) | Out-Null
        }
        $sb.AppendLine() | Out-Null
    }

    if ($Recommendations.Contains("k_collision")) {
        if ($Recommendations.k_collision -gt 1.0) {
            $sb.AppendLine("Duplicates experiment: insertion sort never dominated in tested range.") | Out-Null
        } else {
            $sb.AppendLine("Duplicates experiment: recommend insertion sort when collision ratio >= {0:N2}." -f $Recommendations.k_collision) | Out-Null
        }
        $sb.AppendLine("Per-ratio winners:") | Out-Null
        foreach ($row in $Recommendations.duplicates_summary) {
            $sb.AppendLine(("  ratio={0:N2}: {1} ({2} ms)" -f $row.Parameter, $row.Algorithm, $row.MeanMs)) | Out-Null
        }
        $sb.AppendLine() | Out-Null
    }

    if ($Recommendations.Contains("k_sorted")) {
        if ($Recommendations.k_sorted -gt 1.0) {
            $sb.AppendLine("Sortedness experiment: insertion sort never dominated in tested range.") | Out-Null
        } else {
            $sb.AppendLine("Sortedness experiment: recommend insertion sort when sorted ratio >= {0:N2}." -f $Recommendations.k_sorted) | Out-Null
        }
        $sb.AppendLine("Per-ratio winners:") | Out-Null
        foreach ($row in $Recommendations.sorted_summary) {
            $sb.AppendLine(("  ratio={0:N2}: {1} ({2} ms)" -f $row.Parameter, $row.Algorithm, $row.MeanMs)) | Out-Null
        }
        $sb.AppendLine() | Out-Null
    }

    $sb.AppendLine("Default fallback algorithm: $($Recommendations.default_algorithm)") | Out-Null
    [System.IO.File]::WriteAllText($OutputPath, $sb.ToString())
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = Get-Location }

Push-Location $scriptDir
try {
    if (-not (Test-Path -LiteralPath "$scriptDir\$JavaClass.class")) {
        Write-Host "Compiling $JavaClass.java..."
        & javac "$JavaClass.java"
    }

    $outputDir = Join-Path $scriptDir "experiment_results"
    Ensure-Directory -Path $outputDir

    $random = New-Object System.Random($RandomSeed)
    $z = Get-ConfidenceZ -c $Confidence
    $config = @{
        MinSamples = $MinSamples
        MaxSamples = $MaxSamples
        MaxHalfWidthMs = $MaxHalfWidthMs
        MaxHalfWidthRelative = $MaxHalfWidthRelative
        Z = $z
    }

    $records = New-Object 'System.Collections.Generic.List[object]'

    $digitRecords = Run-Scenario -Scenario 'digits' -Parameters $DigitKs -Generator { param($paramValue, $randomRef) Generate-DigitsSample -Size $ArraySize -Digits $paramValue -Random $randomRef } -Random $random -Config $config -Algorithms $Algorithms -JavaCommand $JavaCommand -JavaClass $JavaClass -WorkDir $scriptDir
    $records.AddRange($digitRecords)

    $dupRecords = Run-Scenario -Scenario 'duplicates' -Parameters $DuplicateRatios -Generator { param($paramValue, $randomRef) Generate-DuplicateSample -Size $ArraySize -TargetRatio $paramValue -Tolerance $DuplicateTolerance -Random $randomRef } -Random $random -Config $config -Algorithms $Algorithms -JavaCommand $JavaCommand -JavaClass $JavaClass -WorkDir $scriptDir
    $records.AddRange($dupRecords)

    $sortedRecords = Run-Scenario -Scenario 'sortedness' -Parameters $SortedRatios -Generator { param($paramValue, $randomRef) Generate-SortedSample -Size $ArraySize -TargetRatio $paramValue -Tolerance $SortedTolerance -Random $randomRef } -Random $random -Config $config -Algorithms $Algorithms -JavaCommand $JavaCommand -JavaClass $JavaClass -WorkDir $scriptDir
    $records.AddRange($sortedRecords)

    $statsPath = Join-Path $outputDir "experiment_statistics.csv"
    $records | Export-Csv -LiteralPath $statsPath -NoTypeInformation -UseQuotes AsNeeded

    $recommendations = Compute-Recommendations -Records $records -Info @{ }
    $summaryPath = Join-Path $outputDir "analysis_summary.txt"
    Write-RecommendationSummary -Recommendations $recommendations -OutputPath $summaryPath

    $configPath = Join-Path $outputDir "search_config.json"
    $json = $recommendations | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($configPath, $json)

    Write-Host "Experiment data saved to:"
    Write-Host "  Statistics: $statsPath"
    Write-Host "  Summary:    $summaryPath"
    Write-Host "  Config:     $configPath"

} finally {
    Pop-Location
}
