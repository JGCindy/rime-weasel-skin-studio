@echo off
chcp 65001 >nul
title Rime tone_display - diagnose and fix
set "TONEMODE=fix"
set "TONEBAT=%~f0"
if /i "%~1"=="diag" set "TONEMODE=diag"
if /i "%~1"=="noredeploy" set "TONEMODE=noredeploy"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8);$m='##'+'PS'+'##';iex $s.Substring($s.IndexOf($m)+6)"
echo.
pause
exit /b
##PS##
# ============================================================
#  Rime 声调显示 tone_display : 诊断 + 修复
#  双击 = 诊断并修复
#  也可以拖到 cmd 里执行:  本文件.bat diag        (只看不改)
#                          本文件.bat noredeploy  (改但不重新部署)
# ============================================================
$ErrorActionPreference = 'Continue'
$mode = if($env:TONEMODE){ $env:TONEMODE } else { 'fix' }
$target = '1'          # 1 = 所有应用一律打开「声起」；0 = 各应用独立
$log  = New-Object 'System.Collections.Generic.List[string]'
function W([string]$s){ [void]$log.Add($s) }
function C([string]$s){ try{ Write-Host $s }catch{} }
function Get-SchemaFiles([string]$dir){
  return @(Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.schema.yaml' -File -EA SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\(build|sync|preview|plum|\.git)\\' })
}
function Get-BuildSchemaFiles([string]$dir){
  $bd = Join-Path $dir 'build'
  if(-not (Test-Path $bd)){ return @() }
  return @(Get-ChildItem -LiteralPath $bd -Filter '*.schema.yaml' -File -EA SilentlyContinue)
}
function Get-ToneResetValue([string]$p){
  try{
    $lines = [IO.File]::ReadAllLines($p)
    for($i=0;$i -lt $lines.Count;$i++){
      if($lines[$i] -match '^\s*-\s*name:\s*tone_display'){
        for($j=$i+1;$j -lt $lines.Count;$j++){
          if($lines[$j] -match '^\s*-\s'){ break }
          if($lines[$j] -match 'reset\s*:\s*([0-9-]+)'){ return ('reset: ' + $matches[1]) }
        }
        return '无 reset 行'
      }
    }
    return '未找到 tone_display'
  }catch{ return '读取失败' }
}
function Set-ToneReset([string]$sp,[string]$rst){
  try{
    $t = [IO.File]::ReadAllText($sp)
    if($t -notmatch 'name:\s*tone_display'){ return 'none' }
    $sl = $t -split "`r?`n"
    for($i=0;$i -lt $sl.Count;$i++){
      if($sl[$i] -match '^\s*-\s*name:\s*tone_display'){
        for($j=$i+1;$j -lt $sl.Count;$j++){
          $l = $sl[$j]
          if($l -match '^\s*-\s'){ break }
          if($l -match '^(\s*)#?\s*reset\s*:\s*[0-9-]+\s*$'){
            $nv = $matches[1] + 'reset: ' + $rst
            if($l -eq $nv){ return 'same' }
            $sl[$j] = $nv
            [IO.File]::WriteAllText($sp,($sl -join "`r`n"),(New-Object Text.UTF8Encoding $false))
            return 'changed'
          }
        }
        $ins = $i
        for($j=$i+1;$j -lt $sl.Count;$j++){
          if($sl[$j] -match '^\s*-\s'){ break }
          $ins = $j
          if($sl[$j] -match '^\s*#?\s*states\s*:'){ break }
        }
        $ind = ([regex]::Match($sl[$i],'^(\s*)')).Groups[1].Value + '  '
        $new = @(); $new += $sl[0..$ins]; $new += ($ind + 'reset: ' + $rst)
        if($ins -lt $sl.Count-1){ $new += $sl[($ins+1)..($sl.Count-1)] }
        [IO.File]::WriteAllText($sp,($new -join "`r`n"),(New-Object Text.UTF8Encoding $false))
        return 'added'
      }
    }
    return 'none'
  }catch{ return ('err: ' + $_.Exception.Message) }
}
function Clean-SaveOptions([string]$p,[string]$keyPat){
  if(-not (Test-Path $p)){ return 'missing' }
  try{
    $lines = [IO.File]::ReadAllText($p) -split "`r?`n"
    $k = -1
    for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match $keyPat){ $k = $i; break } }
    if($k -lt 0){ return 'nokey' }
    $ind = ([regex]::Match($lines[$k],'^(\s*)')).Groups[1].Value
    $end = $k
    for($j=$k+1;$j -lt $lines.Count;$j++){
      $l = $lines[$j]; if($l.Trim() -eq ''){ continue }
      $li = ([regex]::Match($l,'^(\s*)')).Groups[1].Value
      if($li.Length -gt $ind.Length){ $end = $j } else { break }
    }
    $seg = @($lines[$k..$end])
    if(@($seg | Where-Object {$_ -match 'tone_display'}).Count -eq 0){ return 'clean' }
    $items = @($seg | Where-Object {$_ -match '^\s*-\s*'})
    if($items.Count -le 1){ $kept = @() } else { $kept = @($seg | Where-Object {$_ -notmatch 'tone_display'}) }
    $new = @(); if($k -gt 0){ $new += $lines[0..($k-1)] }; $new += $kept
    if($end -lt $lines.Count-1){ $new += $lines[($end+1)..($lines.Count-1)] }
    [IO.File]::WriteAllText($p,($new -join "`r`n"),(New-Object Text.UTF8Encoding $false))
    return 'removed'
  }catch{ return ('err: ' + $_.Exception.Message) }
}
function Fix-UserYaml([string]$p,[string]$rst){
  if(-not (Test-Path $p)){ return 'missing' }
  try{
    $lines = [IO.File]::ReadAllText($p) -split "`r?`n"
    $vi = -1
    for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match '^var:\s*$'){ $vi = $i; break } }
    if($vi -lt 0){ return 'novar' }
    $oi = -1
    for($j=$vi+1;$j -lt $lines.Count;$j++){
      $l = $lines[$j]; if($l.Trim() -eq ''){ continue }
      if($l -notmatch '^\s'){ break }
      if($l -match '^\s+option\s*:\s*$'){ $oi = $j; break }
    }
    if($oi -lt 0){
      $ins = $vi
      for($j=$vi+1;$j -lt $lines.Count;$j++){
        $l = $lines[$j]; if($l.Trim() -eq ''){ continue }
        if($l -notmatch '^\s'){ break }
        $ins = $j
      }
      $new = @(); $new += $lines[0..$ins]; $new += '  option:'
      if($rst -eq '1'){ $new += '    tone_display: true' }
      if($ins -lt $lines.Count-1){ $new += $lines[($ins+1)..($lines.Count-1)] }
      [IO.File]::WriteAllText($p,($new -join "`r`n"),(New-Object Text.UTF8Encoding $false))
      return 'added-option'
    }
    $ti = -1
    for($j=$oi+1;$j -lt $lines.Count;$j++){
      $l = $lines[$j]; if($l.Trim() -eq ''){ continue }
      if($l -notmatch '^\s'){ break }
      if($l -match '^\s+tone_display\s*:'){ $ti = $j; break }
    }
    if($rst -eq '1'){
      if($ti -ge 0){
        $nv = ([regex]::Match($lines[$ti],'^(\s*)')).Groups[1].Value + 'tone_display: true'
        if($lines[$ti] -eq $nv){ return 'same' }
        $lines[$ti] = $nv
        [IO.File]::WriteAllText($p,($lines -join "`r`n"),(New-Object Text.UTF8Encoding $false))
        return 'settrue'
      }
      $ins = $oi
      for($j=$oi+1;$j -lt $lines.Count;$j++){
        $l = $lines[$j]; if($l.Trim() -eq ''){ continue }
        if($l -notmatch '^\s'){ break }
        $ins = $j
      }
      $ind = ([regex]::Match($lines[$ins],'^(\s*)')).Groups[1].Value
      if($ind.Length -le ([regex]::Match($lines[$oi],'^(\s*)')).Groups[1].Value.Length){
        $ind = ([regex]::Match($lines[$oi],'^(\s*)')).Groups[1].Value + '  '
      }
      $new = @(); $new += $lines[0..$ins]; $new += ($ind + 'tone_display: true')
      if($ins -lt $lines.Count-1){ $new += $lines[($ins+1)..($lines.Count-1)] }
      [IO.File]::WriteAllText($p,($new -join "`r`n"),(New-Object Text.UTF8Encoding $false))
      return 'added'
    } else {
      if($ti -ge 0){
        $new = @(); if($ti -gt 0){ $new += $lines[0..($ti-1)] }
        if($ti -lt $lines.Count-1){ $new += $lines[($ti+1)..($lines.Count-1)] }
        [IO.File]::WriteAllText($p,($new -join "`r`n"),(New-Object Text.UTF8Encoding $false))
        return 'removed'
      }
      return 'nothing'
    }
  }catch{ return ('err: ' + $_.Exception.Message) }
}
function Find-Weasel([string]$exe){
  $c = New-Object 'System.Collections.Generic.List[string]'
  foreach($p in @(Get-Process WeaselServer,WeaselDeployer,WeaselSetup -EA SilentlyContinue)){
    try{ $c.Add((Join-Path (Split-Path $p.Path) $exe)) }catch{}
  }
  foreach($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')){
    Get-ChildItem $root -EA SilentlyContinue | ForEach-Object {
      $pp = Get-ItemProperty $_.PSPath -EA SilentlyContinue
      if($pp -and $pp.DisplayName -match '狼毫|Weasel|Rime'){
        if($pp.InstallLocation){ $c.Add((Join-Path $pp.InstallLocation $exe)) }
        if($pp.DisplayIcon){
          $di = $pp.DisplayIcon -replace '^"','' -replace '",.*$','' -replace '^,',''
          if($di -match '\.exe$'){ $c.Add((Join-Path (Split-Path $di) $exe)) }
        }
      }
    }
  }
  $roots = New-Object 'System.Collections.Generic.List[string]'
  if($env:ProgramFiles){ $roots.Add($env:ProgramFiles) }
  if(${env:ProgramFiles(x86)}){ $roots.Add(${env:ProgramFiles(x86)}) }
  if($env:LOCALAPPDATA){ $roots.Add((Join-Path $env:LOCALAPPDATA 'Programs')) }
  foreach($drv in @('C:','D:','E:','F:')){
    $roots.Add($drv + '\Program Files'); $roots.Add($drv + '\Program Files (x86)')
  }
  foreach($r in ($roots | Select-Object -Unique)){
    if(-not (Test-Path $r)){ continue }
    $c.Add((Join-Path $r $exe))
    $b = Join-Path $r 'Rime'
    if(Test-Path $b){
      Get-ChildItem $b -Directory -EA SilentlyContinue | ForEach-Object { $c.Add((Join-Path $_.FullName $exe)) }
    }
    Get-ChildItem $r -Directory -Filter 'weasel-*' -EA SilentlyContinue | ForEach-Object { $c.Add((Join-Path $_.FullName $exe)) }
  }
  foreach($x in ($c | Select-Object -Unique)){ if($x -and (Test-Path $x)){ return $x } }
  return $null
}

$now = Get-Date
W ('Rime 声调显示（tone_display）诊断报告        生成时间 ' + $now.ToString('yyyy-MM-dd HH:mm:ss'))
W ('执行模式: ' + $mode + '      脚本目标: reset = ' + $target + '（1 = 所有应用都开「声起」）')
W ('脚本文件: ' + $env:TONEBAT)
W '=================================================================='
W ''

W '【0】环境'
W ('  PowerShell    : ' + $PSVersionTable.PSVersion.ToString())
W ('  系统          : ' + [Environment]::OSVersion.VersionString)
W ('  当前用户      : ' + $env:USERNAME)
$ws = @(Get-Process WeaselServer -EA SilentlyContinue)
if($ws.Count -gt 0){
  foreach($p in $ws){
    try{ W ('  WeaselServer  : 运行中  PID ' + $p.Id + '   路径 ' + $p.Path) }
    catch{ W ('  WeaselServer  : 运行中  PID ' + $p.Id + ' （路径读不到）') }
  }
} else {
  W '  WeaselServer  : 未运行   <<< 服务没起来的话，改什么都不会生效'
}
foreach($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')){
  Get-ChildItem $root -EA SilentlyContinue | ForEach-Object {
    $pp = Get-ItemProperty $_.PSPath -EA SilentlyContinue
    if($pp -and $pp.DisplayName -match '狼毫|Weasel|Rime'){
      W ('  已安装        : ' + $pp.DisplayName + '  版本 ' + $pp.DisplayVersion + '  位置 ' + $pp.InstallLocation)
    }
  }
}
W ''

W '【1】用户资料夹候选（决定脚本改哪里）'
$cands = New-Object 'System.Collections.Generic.List[string]'
try{
  $rk = 'HKCU:\Software\Rime\Weasel'
  if(Test-Path $rk){
    $rv = (Get-ItemProperty $rk -EA SilentlyContinue).RimeUserDir
    W ('  注册表 HKCU\Software\Rime\Weasel\RimeUserDir = ' + $rv)
    if($rv){ $cands.Add($rv) }
  } else {
    W '  注册表 HKCU\Software\Rime\Weasel 不存在'
  }
}catch{ W ('  读注册表失败: ' + $_.Exception.Message) }
if($env:RIME_USER_DATA_DIR){
  W ('  环境变量 RIME_USER_DATA_DIR = ' + $env:RIME_USER_DATA_DIR)
  $cands.Add($env:RIME_USER_DATA_DIR)
}
$defDir = Join-Path $env:APPDATA 'Rime'
W ('  %APPDATA%\Rime = ' + $defDir)
$cands.Add($defDir)
foreach($p in @(Get-Process WeaselServer,WeaselDeployer -EA SilentlyContinue)){
  try{
    $d = Split-Path $p.Path
    foreach($x in @($d,(Split-Path $d))){
      $rc = Join-Path $x 'Rime'
      if(Test-Path $rc){ W ('  安装目录旁的 Rime（便携模式）= ' + $rc); $cands.Add($rc) }
    }
  }catch{}
}
$cands = @($cands | Where-Object {$_ -and ($_.Trim() -ne '')} | Select-Object -Unique)
if($env:TONEDIR){
  W ('  环境变量 TONEDIR = ' + $env:TONEDIR + '  → 只处理这一个目录')
  $cands = @($env:TONEDIR)
}
W ''

W '【2】各候选目录扫描'
$rows = @()
foreach($d in $cands){
  if(-not (Test-Path $d)){ W ('  [不存在] ' + $d); continue }
  $src = Get-SchemaFiles $d
  $tone = @($src | Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'name:\s*tone_display' -Quiet -EA SilentlyContinue })
  $bd = Join-Path $d 'build'
  $hasB = Test-Path $bd
  $bs = Get-BuildSchemaFiles $d
  $bt = @($bs | Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'name:\s*tone_display' -Quiet -EA SilentlyContinue })
  $rows += [pscustomobject]@{ Dir=$d; Src=$src.Count; SrcTone=$tone.Count; HasBuild=$hasB; BuildTone=$bt.Count }
  W ('  [存在] ' + $d)
  W ('         源 schema ' + $src.Count + ' 个，其中含 tone_display ' + $tone.Count + ' 个')
  W ('         build 目录 ' + $(if($hasB){'有'}else{'无'}) + '，build 里含 tone_display 的编译产物 ' + $bt.Count + ' 个')
}
$active = $rows | Where-Object { $_.SrcTone -gt 0 } | Select-Object -First 1
if(-not $active){ $active = $rows | Where-Object { $_.Src -gt 0 } | Select-Object -First 1 }
if(-not $active){ $active = $rows | Select-Object -First 1 }
if($cands | Where-Object { Test-Path (Join-Path $_ 'sync') }){
  W '  注: 有目录含 sync\（Rime 的同步快照，只是备份，不参与加载，已忽略）'
}
if(-not $active){
  W ''
  W '!! 没有找到任何 Rime 用户资料夹，无法继续。请确认小狼毫已安装并至少部署过一次。'
} else {
  $rime = $active.Dir
  W ''
  W '【3】活跃目录明细'
  W ('  活跃目录 = ' + $rime)
  W ''
  $srcFiles = Get-SchemaFiles $rime
  $srcTone  = @($srcFiles | Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'name:\s*tone_display' -Quiet -EA SilentlyContinue })
  $srcNoT   = @($srcFiles | Where-Object { -not (Select-String -LiteralPath $_.FullName -Pattern 'name:\s*tone_display' -Quiet -EA SilentlyContinue) })
  W ('  [3.1] 源方案文件  共 ' + $srcFiles.Count + ' 个，含 tone_display ' + $srcTone.Count + ' 个')
  foreach($f in $srcTone){
    W ('        ' + $f.Name.PadRight(34) + ' ' + (Get-ToneResetValue $f.FullName).PadRight(14) + ' 改动于 ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
  }
  if($srcNoT.Count -gt 0){
    W ('        以下方案没有 tone_display 开关，它们本来就不支持「声」（正常）：')
    W ('        ' + (($srcNoT | ForEach-Object { $_.Name }) -join ', '))
  }
  $bd = Join-Path $rime 'build'
  if(Test-Path $bd){
    $bs = Get-BuildSchemaFiles $rime
    $bt = @($bs | Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'name:\s*tone_display' -Quiet -EA SilentlyContinue })
    W ''
    W ('  [3.2] build 编译产物  共 ' + $bs.Count + ' 个，含 tone_display ' + $bt.Count + ' 个')
    foreach($f in $bt){
      W ('        ' + $f.Name.PadRight(34) + ' ' + (Get-ToneResetValue $f.FullName).PadRight(14) + ' 改动于 ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
    }
    $newest = $bs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($newest){ W ('        最近一次编译产物更新: ' + $newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) }
  } else {
    W ''
    W '  [3.2] build 目录不存在（从未部署过，或者部署从未成功）'
  }
  W ''
  W '  [3.3] 其它可能干扰的因素'
  $lua = Join-Path $rime 'lua\super_preedit.lua'
  if(Test-Path $lua){ W ('        lua\super_preedit.lua : 存在（「声」的显示就靠它）') }
  else { W ('        lua\super_preedit.lua : 缺失 <<< 少了它，开关拨到「声起」也不会显示声调') }
  $uy = Join-Path $rime 'user.yaml'
  if(Test-Path $uy){
    $uyHit = Select-String -LiteralPath $uy -Pattern 'tone_display' -EA SilentlyContinue
    if($uyHit){
      $uyLines = @($uyHit | ForEach-Object { $_.Line.Trim() })
      W ('        user.yaml : ' + ($uyLines -join ' | '))
    }
    else { W '        user.yaml : 无 tone_display 记录' }
  } else { W '        user.yaml : 不存在' }
  $dc = Join-Path $rime 'default.custom.yaml'
  if(Test-Path $dc){
    $dHit = Select-String -LiteralPath $dc -Pattern 'tone_display' -EA SilentlyContinue
    if($dHit){ W ('        default.custom.yaml 里有 tone_display（save_options 残留，会让「声」在新会话被还原掉）') }
    else { W '        default.custom.yaml : 无 tone_display' }
  } else { W '        default.custom.yaml : 不存在' }
  $bdYaml = Join-Path $bd 'default.yaml'
  if(Test-Path $bdYaml){
    $bHit = Select-String -LiteralPath $bdYaml -Pattern 'tone_display' -EA SilentlyContinue
    if($bHit){ W '        build\default.yaml 里有 tone_display（同上，残留）' }
    else { W '        build\default.yaml : 无 tone_display' }
  }
  $cust = @(Get-ChildItem -LiteralPath $rime -Recurse -Filter '*.custom.yaml' -File -EA SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(build|sync|preview|plum|\.git)\\' })
  $sus = @()
  foreach($f in $cust){
    $n = 0
    foreach($l in ([IO.File]::ReadAllLines($f.FullName))){
      $t = $l.Trim()
      if($t.StartsWith('#')){ continue }
      if($l -match '^\s*-\s*tone_display\s*$'){ continue }   # save_options 里的列表项，不算覆盖
      if($l -match 'switches'){ $n++; continue }
      if($l -match 'tone_display'){ $n++ }
    }
    if($n -gt 0){ $sus += ($f.Name + '(' + $n + ' 处)') }
  }
  if($sus.Count -gt 0){
    W ('        ! 这些 custom.yaml 里出现了 switches / tone_display，可能覆盖方案设置：')
    W ('          ' + ($sus -join ', '))
  } else {
    W '        没有 custom.yaml 覆盖 switches（好）'
  }
  W ''
  W '  [3.4] 当前启用的方案（schema_list）'
  $listSrc = $null
  if(Test-Path $dc){
    if(Select-String -LiteralPath $dc -Pattern 'schema_list' -Quiet -EA SilentlyContinue){ $listSrc = $dc }
  }
  if(-not $listSrc -and (Test-Path $bdYaml)){
    if(Select-String -LiteralPath $bdYaml -Pattern 'schema_list' -Quiet -EA SilentlyContinue){ $listSrc = $bdYaml }
  }
  if($listSrc){
    W ('        来源: ' + $listSrc)
    $inList = $false; $got = 0
    foreach($l in ([IO.File]::ReadAllLines($listSrc))){
      if($l -match '^\s*schema_list\s*:'){ $inList = $true; continue }
      if($inList){
        if($l -match '^\s*-\s*schema:\s*(\S+)'){ W ('          ' + $matches[1]); $got++ }
        elseif($l -match '^\s*\S'){ $inList = $false }
      }
    }
    if($got -eq 0){ W '          （读不到列表，可能用的是内置默认方案）' }
  } else { W '        default.custom.yaml / build\default.yaml 里都没有 schema_list，用的是内置默认方案列表' }

  if($mode -eq 'diag'){
    W ''
    W '【4】修复  —— 已跳过（diag 模式只看不改）'
  } else {
    W ''
    W '【4】修复'
    $ch = 0; $same = 0; $none = 0
    W '  [4.1] 源方案 reset'
    foreach($f in $srcTone){
      $r = Set-ToneReset $f.FullName $target
      if($r -eq 'changed'){ $ch++; W ('        [已改] ' + $f.Name + '  reset -> ' + $target) }
      elseif($r -eq 'added'){ $ch++; W ('        [新增] ' + $f.Name + '  补上 reset: ' + $target) }
      elseif($r -eq 'same'){ $same++; W ('        [原本就对] ' + $f.Name) }
      else { W ('        [异常] ' + $f.Name + '  ' + $r) }
    }
    W ('        小计: 改了 ' + $ch + ' 个，本来就对 ' + $same + ' 个')
    W '  [4.2] build 编译产物 reset'
    if(Test-Path $bd){
      $bs2 = Get-BuildSchemaFiles $rime
      $bc = 0
      foreach($f in $bs2){
        $r = Set-ToneReset $f.FullName $target
        if($r -eq 'changed'){ $bc++; W ('        [已改] build\' + $f.Name) }
        elseif($r -eq 'added'){ $bc++; W ('        [新增] build\' + $f.Name) }
      }
      W ('        小计: 改了 ' + $bc + ' / 共 ' + $bs2.Count + ' 个编译产物')
    } else { W '        无 build 目录，跳过' }
    W '  [4.3] 清理 save_options 里的 tone_display（历史遗留，会让设置在新会话被还原）'
    $r1 = Clean-SaveOptions $dc '^\s*["'']?switcher/save_options["'']?\s*:'
    W ('        default.custom.yaml : ' + $r1)
    $r2 = Clean-SaveOptions $bdYaml '^\s*save_options\s*:'
    W ('        build\default.yaml  : ' + $r2)
    W '  [4.4] user.yaml 里的选项记录（保险：让新会话也倾向「开」）'
    if(Test-Path $uy){
      Copy-Item $uy ($uy + '.bak-tonefix') -Force -EA SilentlyContinue
      $r3 = Fix-UserYaml $uy $target
      W ('        user.yaml : ' + $r3 + '（已备份 user.yaml.bak-tonefix）')
    } else { W '        user.yaml 不存在，跳过' }
    W ''
    W '  [4.5] 重新部署'
    if($mode -eq 'noredeploy'){
      W '        已跳过（noredeploy 模式）。请手动右键托盘图标 → 重新部署。'
    } else {
      $dep = Find-Weasel 'WeaselDeployer.exe'
      if($dep){
        W ('        部署器: ' + $dep)
        try{
          $pr = Start-Process -FilePath $dep -ArgumentList '/deploy' -PassThru -EA Stop
          if($pr){ $pr | Wait-Process -Timeout 240 -EA SilentlyContinue }
          W '        已触发重新部署并等待其结束'
        }catch{
          W ('        启动部署器失败: ' + $_.Exception.Message)
          W '        请手动右键托盘图标 → 重新部署。'
        }
      } else {
        W '        ! 没找到 WeaselDeployer.exe —— 这就是「源文件改了却没生效」的典型原因。'
        W '        请手动右键任务栏托盘的小狼毫图标 → 重新部署。'
      }
    }
  }

  W ''
  W '【5】复核'
  Start-Sleep -Seconds 2
  W '  [5.1] 源方案'
  foreach($f in (Get-SchemaFiles $rime)){
    if(Select-String -LiteralPath $f.FullName -Pattern 'name:\s*tone_display' -Quiet -EA SilentlyContinue){
      W ('        ' + $f.Name.PadRight(34) + ' ' + (Get-ToneResetValue $f.FullName))
    }
  }
  W '  [5.2] build 编译产物'
  if(Test-Path $bd){
    foreach($f in (Get-BuildSchemaFiles $rime)){
      if(Select-String -LiteralPath $f.FullName -Pattern 'name:\s*tone_display' -Quiet -EA SilentlyContinue){
        W ('        ' + $f.Name.PadRight(34) + ' ' + (Get-ToneResetValue $f.FullName))
      }
    }
  }
  W '  [5.3] 服务状态'
  $ws2 = @(Get-Process WeaselServer -EA SilentlyContinue)
  if($ws2.Count -gt 0){ W '        WeaselServer 运行中，配置已重载' } else { W '        ! WeaselServer 未运行，请从开始菜单启动小狼毫' }
  W ''
  W '【结论】'
  $bad = 0
  foreach($f in (Get-SchemaFiles $rime)){
    if(Select-String -LiteralPath $f.FullName -Pattern 'name:\s*tone_display' -Quiet -EA SilentlyContinue){
      $v = Get-ToneResetValue $f.FullName
      if($v -ne ('reset: ' + $target)){ $bad++ }
    }
  }
  if($bad -eq 0){
    W ('        所有含 tone_display 的方案文件，reset 都已是 ' + $target + '。')
    W '        请关掉所有应用（记事本/浏览器/微信…）再打开，随便打几个字看看是否显示带声调的拼音。'
    W '        若仍不显示：把本报告发回给作者，重点看【2】里是否有多个用户资料夹。'
  } else {
    W ('        仍有 ' + $bad + ' 个文件没改成 ' + $target + '，多半是权限或被别的程序占用。')
    W '        把本报告发回给作者。'
  }
}

W ''
W '=================================================================='
$desk = [Environment]::GetFolderPath('Desktop')
if(-not $desk){ $desk = $env:USERPROFILE }
$rp = Join-Path $desk ('rime-tone-report-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
try{
  [IO.File]::WriteAllText($rp, ($log -join "`r`n"), (New-Object Text.UTF8Encoding $true))
  C ''
  C 'Report saved to:'
  C $rp
  try{ Start-Process notepad.exe -ArgumentList ('"' + $rp + '"') }catch{}
}catch{
  C ''
  C ('Report file failed: ' + $_.Exception.Message)
  C 'Printing to console instead:'
  $log | ForEach-Object { C $_ }
}
