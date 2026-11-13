<#
.SYNOPSIS
    Сбор оценок 1-2-1 из блоков ```yaml в отчетах employees\*\ГГГГ-ММ.md.

.EXAMPLE
    .\scripts\summary.ps1 -Month 2026-10
    Таблица оценок за месяц (markdown) для summaries\2026-10.md.

.EXAMPLE
    .\scripts\summary.ps1 -Csv ratings.csv
    Все встречи в CSV (UTF-8 с BOM, открывается в Excel) для графиков и дашборда.

.EXAMPLE
    .\scripts\summary.ps1 -Check
    Проверка, что блок yaml совпадает с полями отчета.

.NOTES
    Работает в Windows PowerShell 5.1 и PowerShell 7+.
    Файл сохранен в UTF-8 с BOM: без BOM Windows PowerShell 5.1 неверно читает кириллицу.
#>
[CmdletBinding(DefaultParameterSetName = 'Help')]
param(
    [Parameter(ParameterSetName = 'Month', Mandatory = $true)]
    [ValidatePattern('^\d{4}-\d{2}$')]
    [string]$Month,

    [Parameter(ParameterSetName = 'Csv', Mandatory = $true)]
    [string]$Csv,

    [Parameter(ParameterSetName = 'Check', Mandatory = $true)]
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Root = Split-Path -Parent $PSScriptRoot
$Fields = [ordered]@{
    motivation   = 'Мотивация'
    burnout      = 'Выгорание'
    satisfaction = 'Удовлетворённость'
    blocker      = 'Категория блокера'
}

function Get-Meetings {
    $rows = New-Object System.Collections.Generic.List[object]
    $employeesDir = Join-Path $Root 'employees'
    foreach ($dir in (Get-ChildItem -Path $employeesDir -Directory | Sort-Object Name)) {
        $files = Get-ChildItem -Path $dir.FullName -Filter '*.md' -File |
            Where-Object { $_.BaseName -match '^\d{4}-\d{2}$' } | Sort-Object Name
        foreach ($file in $files) {
            $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8) -replace "`r`n", "`n"
            $title = [regex]::Match($text, '(?m)^# 1-2-1: (.+?) —')
            $name = if ($title.Success) { $title.Groups[1].Value.Trim() } else { $dir.Name }
            $blocks = [regex]::Split($text, '(?m)(?=^## Встреча )') | Select-Object -Skip 1
            foreach ($block in $blocks) {
                $meta = [regex]::Match($block, '(?s)```yaml\n(.*?)```')
                if (-not $meta.Success) { continue }
                $row = [ordered]@{}
                foreach ($kv in [regex]::Matches($meta.Groups[1].Value, '(?m)^(\w+):[ \t]*(.+?)[ \t]*$')) {
                    $row[$kv.Groups[1].Value] = $kv.Groups[2].Value
                }
                $row['employee'] = $name
                $row['folder'] = $dir.Name
                $row['month'] = $file.BaseName
                $row['block'] = $block
                $rows.Add([pscustomobject]$row)
            }
        }
    }
    return @($rows | Sort-Object folder, date)
}

function Format-Delta($cur, $prev, [string]$key) {
    if ($null -eq $prev) { return [string]$cur.$key }
    $d = [int]$cur.$key - [int]$prev.$key
    if ($d -eq 0) { return [string]$cur.$key }
    $arrow = if ($d -gt 0) { [char]0x2191 } else { [char]0x2193 }
    return ('{0} ({1}{2})' -f $cur.$key, $arrow, [math]::Abs($d))
}

function Show-MonthTable([string]$month) {
    $rows = Get-Meetings
    $entries = foreach ($group in ($rows | Group-Object folder)) {
        $meetings = @($group.Group | Sort-Object date)
        $inMonth = @($meetings | Where-Object { $_.month -eq $month })
        if ($inMonth.Count -eq 0) { continue }
        $cur = $inMonth[-1]
        $first = $inMonth[0].date
        $earlier = @($meetings | Where-Object { [string]::CompareOrdinal($_.date, $first) -lt 0 })
        $prev = if ($earlier.Count -gt 0) { $earlier[-1] } else { $null }
        [pscustomobject]@{
            employee = $cur.employee
            line     = '| {0} | {1} | {2} | {3} | {4} | {5} |' -f $cur.employee, $cur.date,
                (Format-Delta $cur $prev 'motivation'), (Format-Delta $cur $prev 'burnout'),
                (Format-Delta $cur $prev 'satisfaction'), $cur.blocker
        }
    }
    $lines = @('| Сотрудник | Встреча | Мотивация | Выгорание | Удовлетворённость | Блокер |',
               '|---|---|---|---|---|---|')
    $lines += @($entries | Sort-Object employee | ForEach-Object { $_.line })
    $lines -join "`n"
}

function Export-Ratings([string]$path) {
    if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path (Get-Location).Path $path }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('date,employee,folder,motivation,burnout,satisfaction,blocker')
    foreach ($r in (Get-Meetings)) {
        $values = @($r.date, $r.employee, $r.folder, $r.motivation, $r.burnout, $r.satisfaction, $r.blocker) |
            ForEach-Object { '"' + ([string]$_ -replace '"', '""') + '"' }
        [void]$sb.AppendLine($values -join ',')
    }
    [System.IO.File]::WriteAllText($path, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))
    "CSV сохранен: $path"
}

function Test-Reports {
    $ok = $true
    foreach ($r in (Get-Meetings)) {
        foreach ($key in $Fields.Keys) {
            $pattern = '(?m)^\*\*' + [regex]::Escape($Fields[$key]) + ':\*\* (.+?)[ \t]*$'
            $m = [regex]::Match($r.block, $pattern)
            $actual = if ($m.Success) { $m.Groups[1].Value.Trim() } else { $null }
            if ($actual -ne $r.$key) {
                $ok = $false
                "{0} {1}: {2}='{3}', в отчете '{4}'" -f $r.folder, $r.date, $key, $r.$key, $actual
            }
        }
    }
    if ($ok) { 'OK' } else { 'Найдены расхождения' }
    if (-not $ok) { exit 1 }
}

switch ($PSCmdlet.ParameterSetName) {
    'Month' { Show-MonthTable $Month }
    'Csv'   { Export-Ratings $Csv }
    'Check' { Test-Reports }
    default { Get-Help $PSCommandPath -Detailed }
}
