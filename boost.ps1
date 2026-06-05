# =====================================================================
#  Soft Projetos - Boost  |  Otimizador do Windows  (v1.0.0)
#  Uso:  irm boost.softprojetos.com | iex
#  - Limpeza de tranqueiras (debloat), privacidade/telemetria e jogos
#  - Tudo reversível; cria ponto de restauração antes de aplicar
#  - Log em %TEMP%\SoftProjetos-Boost
# =====================================================================

# ---- Garantir Administrador + STA (WPF exige STA) ----
$idn = [Security.Principal.WindowsIdentity]::GetCurrent()
$prc = New-Object Security.Principal.WindowsPrincipal($idn)
$isAdmin = $prc.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSTA   = [Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'
if (-not $isAdmin -or -not $isSTA) {
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden',
            '-Command','[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; irm boost.softprojetos.com | iex')
    } catch { Write-Host 'Cancelado (precisa de Administrador).' -ForegroundColor Yellow }
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---- Log ----
$script:LogDir  = Join-Path $env:TEMP 'SoftProjetos-Boost'
New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
$script:LogFile = Join-Path $script:LogDir ("boost_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

# ---- Helpers ----
function Set-Reg {
    param([string]$Path,[string]$Name,$Value,[string]$Type='DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}
function Remove-Reg {
    param([string]$Path,[string]$Name)
    if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
}
function Test-Reg {
    param([string]$Path,[string]$Name,$Value)
    try { return ((Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name -eq $Value) }
    catch { return $false }
}
function Brush { param([string]$hex) (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex) }
function Thk   { param($l,$t,$r,$b) New-Object System.Windows.Thickness($l,$t,$r,$b) }

# ---- Apps instalados (cache pra Test rápido) ----
$script:Installed = @{}
$script:InstalledReady = $false

# ---- Ponto de restauração ----
function Set-MouseAccel([bool]$Enabled) {
    if ($Enabled) { $s='1'; $t1='6'; $t2='10'; $arr=@(6,10,1) } else { $s='0'; $t1='0'; $t2='0'; $arr=@(0,0,0) }
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' $s 'String'
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' $t1 'String'
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' $t2 'String'
    try {
        if (-not ([System.Management.Automation.PSTypeName]'Boost.MouseNative').Type) {
            Add-Type -Namespace Boost -Name MouseNative -MemberDefinition '[DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint a, uint b, int[] c, uint d);'
        }
        [void][Boost.MouseNative]::SystemParametersInfo(4, 0, [int[]]$arr, 3)
    } catch {}
}
function Set-VisualFX([bool]$Performance) {
    $d='HKCU:\Control Panel\Desktop'; $wm='HKCU:\Control Panel\Desktop\WindowMetrics'
    $adv='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $dwm='HKCU:\Software\Microsoft\Windows\DWM'
    $vfx='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    if ($Performance) {
        $cur = (Get-ItemProperty $d -ErrorAction SilentlyContinue).UserPreferencesMask
        $bak = (Get-ItemProperty 'HKCU:\Software\SoftProjetosBoost' -ErrorAction SilentlyContinue).UPMbak
        if ($cur -and -not $bak) { Set-Reg 'HKCU:\Software\SoftProjetosBoost' 'UPMbak' $cur 'Binary' }
        Set-Reg $vfx 'VisualFXSetting' 3
        Set-Reg $d 'UserPreferencesMask' ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) 'Binary'
        Set-Reg $d 'DragFullWindows' '0' 'String'
        Set-Reg $d 'FontSmoothing' '2' 'String'
        Set-Reg $wm 'MinAnimate' '0' 'String'
        Set-Reg $adv 'ListviewAlphaSelect' 0
        Set-Reg $adv 'ListviewShadow' 0
        Set-Reg $adv 'TaskbarAnimations' 0
        Set-Reg $dwm 'EnableAeroPeek' 0
        Set-Reg $dwm 'AlwaysHibernateThumbnails' 0
    } else {
        $bak = (Get-ItemProperty 'HKCU:\Software\SoftProjetosBoost' -ErrorAction SilentlyContinue).UPMbak
        if ($bak) { Set-Reg $d 'UserPreferencesMask' $bak 'Binary' }
        else { Set-Reg $d 'UserPreferencesMask' ([byte[]](0x9E,0x1E,0x07,0x80,0x12,0x00,0x00,0x00)) 'Binary' }
        Set-Reg $vfx 'VisualFXSetting' 0
        Set-Reg $d 'DragFullWindows' '1' 'String'
        Set-Reg $wm 'MinAnimate' '1' 'String'
        Set-Reg $adv 'ListviewAlphaSelect' 1
        Set-Reg $adv 'ListviewShadow' 1
        Set-Reg $adv 'TaskbarAnimations' 1
        Set-Reg $dwm 'EnableAeroPeek' 1
        Set-Reg $dwm 'AlwaysHibernateThumbnails' 1
    }
    # --- aplica na sessao viva via API oficial (SystemParametersInfo); a UserPreferencesMask
    #     eh cacheada pelo USER32 no logon, entao SPI_SET forca aplicar agora sem deslogar ---
    try {
        if (-not ([System.Management.Automation.PSTypeName]'Boost.Spi').Type) {
            Add-Type -Namespace Boost -Name Spi -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint a, uint b, System.IntPtr c, uint d);
[StructLayout(LayoutKind.Sequential)] public struct ANIMATIONINFO { public uint cbSize; public int iMinAnimate; }
[DllImport("user32.dll", SetLastError=true, EntryPoint="SystemParametersInfo")] public static extern bool SpiAnimation(uint a, uint b, ref ANIMATIONINFO c, uint d);
'@
        }
        $send = [uint32]0x2
        if ($Performance) { $ui = [IntPtr]::Zero; $drag = [uint32]0; $anim = 0 } else { $ui = [IntPtr]::new(1); $drag = [uint32]1; $anim = 1 }
        [void][Boost.Spi]::SystemParametersInfo(0x103F, 0, $ui, $send)
        [void][Boost.Spi]::SystemParametersInfo(0x0025, $drag, [IntPtr]::Zero, $send)
        $ai = New-Object Boost.Spi+ANIMATIONINFO; $ai.cbSize = [uint32]8; $ai.iMinAnimate = $anim
        [void][Boost.Spi]::SpiAnimation(0x0049, [uint32]8, [ref]$ai, $send)
    } catch {}
}
function New-BoostRestorePoint {
    try {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'Soft Projetos Boost' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        return $true
    } catch { return $false }
}

# =====================================================================
#  TWEAKS
# =====================================================================
$reg = @(
  [pscustomobject]@{ Id='telemetry'; Cat='Privacidade & Telemetria'; Name='Desativar telemetria do Windows'; Default=$true; Reboot=$false
    Desc='AllowTelemetry=0 e serviço DiagTrack desativado. Em edições Home/Pro o Windows mantém um nível mínimo de coleta.'
    Apply={ param($t) foreach($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection','HKCU:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'){ Set-Reg $k 'AllowTelemetry' 0 }
            Set-Service 'DiagTrack' -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service 'DiagTrack' -Force -ErrorAction SilentlyContinue }
    Revert={ param($t) foreach($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection','HKCU:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'){ Remove-Reg $k 'AllowTelemetry' }
             Set-Service 'DiagTrack' -StartupType Automatic -ErrorAction SilentlyContinue
             Start-Service 'DiagTrack' -ErrorAction SilentlyContinue }
    Test={ param($t) Test-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0 } }

  [pscustomobject]@{ Id='advid'; Cat='Privacidade & Telemetria'; Name='Desativar ID de publicidade'; Default=$true; Reboot=$false
    Desc='Impede apps de usarem o ID de publicidade para anúncios personalizados.'
    Apply={ param($t) Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0; Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CPSS\Store\AdvertisingInfo' 'Value' 0 }
    Revert={ param($t) Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 1; Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CPSS\Store\AdvertisingInfo' 'Value' 1 }
    Test={ param($t) Test-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 } }

  [pscustomobject]@{ Id='tailored'; Cat='Privacidade & Telemetria'; Name='Desativar experiências personalizadas'; Default=$true; Reboot=$false
    Desc='Desliga sugestões baseadas em dados de diagnóstico.'
    Apply={ param($t) Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 }
    Revert={ param($t) Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 1 }
    Test={ param($t) Test-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 } }

  [pscustomobject]@{ Id='suggestions'; Cat='Privacidade & Telemetria'; Name='Desativar conteúdo sugerido e apps automáticos'; Default=$true; Reboot=$false
    Desc='Para sugestões no Iniciar/Configurações e a instalação silenciosa de apps promovidos.'
    Apply={ param($t) $p='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            foreach($n in 'SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SubscribedContent-310093Enabled','SubscribedContent-338387Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-338393Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SubscribedContent-353698Enabled','PreInstalledAppsEnabled','OemPreInstalledAppsEnabled','ContentDeliveryAllowed','RotatingLockScreenEnabled','SoftLandingEnabled','FeatureManagementEnabled'){ Set-Reg $p $n 0 } }
    Revert={ param($t) $p='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            foreach($n in 'SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SubscribedContent-310093Enabled','SubscribedContent-338387Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-338393Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SubscribedContent-353698Enabled','PreInstalledAppsEnabled','OemPreInstalledAppsEnabled','ContentDeliveryAllowed','RotatingLockScreenEnabled','SoftLandingEnabled','FeatureManagementEnabled'){ Set-Reg $p $n 1 } }
    Test={ param($t) Test-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0 } }

  [pscustomobject]@{ Id='websearch'; Cat='Privacidade & Telemetria'; Name='Tirar resultados da web do menu Iniciar'; Default=$true; Reboot=$false
    Desc='Remove sugestões/Bing da busca do menu Iniciar (Win10 e Win11). Só resultados locais.'
    Apply={ param($t) Set-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
            Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
            Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0 }
    Revert={ param($t) Remove-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions'
             Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 1 }
    Test={ param($t) (Test-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0) -or (Test-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1) } }

  [pscustomobject]@{ Id='ultimateperf'; Cat='Desempenho & Jogos'; Name='Plano de energia Desempenho Máximo'; Default=$true; Reboot=$false
    Desc='Ativa o plano Ultimate Performance (mais energia, menos throttle). Ideal em desktop.'
    Apply={ param($t) $tmpl='e9a42b02-d5df-448d-aa00-03f14749eb61'; $dst='5f3e1a7c-9b2d-4e86-a1c4-7d0f2b8e6a93'; powercfg -duplicatescheme $tmpl $dst 2>$null | Out-Null; powercfg -setactive $dst 2>$null | Out-Null; if (-not (((powercfg /getactivescheme) -join ' ').ToLower().Contains($dst))) { $out=(powercfg -duplicatescheme $tmpl 2>$null) -join ' '; $g=([regex]'[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Match($out).Value; if ($g) { powercfg -setactive $g 2>$null | Out-Null } } }
    Revert={ param($t) powercfg -setactive '381b4222-f694-41f0-9685-ff5bb260df2e' 2>$null | Out-Null }
    Test={ param($t) ((powercfg /getactivescheme) -join ' ').ToLower().Contains('5f3e1a7c-9b2d-4e86-a1c4-7d0f2b8e6a93') } }

  [pscustomobject]@{ Id='hags'; Cat='Desempenho & Jogos'; Name='Hardware-accelerated GPU Scheduling (HAGS)'; Default=$true; Reboot=$true
    Desc='Liga o agendamento de GPU por hardware (HwSchMode=2). Reduz overhead de CPU. Exige REINICIAR e GPU compatível.'
    Apply={ param($t) Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 }
    Revert={ param($t) Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1 }
    Test={ param($t) Test-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 } }

  [pscustomobject]@{ Id='gamemode'; Cat='Desempenho & Jogos'; Name='Ativar Game Mode'; Default=$true; Reboot=$false
    Desc='Liga o Modo Jogo do Windows (prioriza recursos para o jogo em foco).'
    Apply={ param($t) Set-Reg 'HKCU:\SOFTWARE\Microsoft\GameBar' 'AutoGameModeEnabled' 1 }
    Revert={ param($t) Set-Reg 'HKCU:\SOFTWARE\Microsoft\GameBar' 'AutoGameModeEnabled' 0 }
    Test={ param($t) Test-Reg 'HKCU:\SOFTWARE\Microsoft\GameBar' 'AutoGameModeEnabled' 1 } }

  [pscustomobject]@{ Id='gamedvr'; Cat='Desempenho & Jogos'; Name='Desativar Game DVR (gravação em segundo plano)'; Default=$true; Reboot=$false
    Desc='Desliga a gravação em segundo plano do Game Bar, que consome CPU/GPU durante o jogo.'
    Apply={ param($t) Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0 }
    Revert={ param($t) Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1
             Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1
             Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' }
    Test={ param($t) Test-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 } }

  [pscustomobject]@{ Id='mouseaccel'; Cat='Desempenho & Jogos'; Name='Mouse 1:1 (desligar aceleracao do ponteiro)'; Default=$true; Reboot=$false
    Desc='Desliga a aceleracao do ponteiro (Enhance Pointer Precision). O mouse fica 1:1 - essencial pra mira em jogos. Aplica na hora.'
    Apply={ param($t) Set-MouseAccel $false }
    Revert={ param($t) Set-MouseAccel $true }
    Test={ param($t) Test-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' } }

  [pscustomobject]@{ Id='sysresponsiveness'; Cat='Desempenho & Jogos'; Name='Liberar CPU reservada pra tarefas de fundo'; Default=$true; Reboot=$false
    Desc='SystemResponsiveness=0: o Windows deixa de reservar ~20% da CPU pra tarefas de fundo, liberando mais pro jogo em foco.'
    Apply={ param($t) Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0 }
    Revert={ param($t) Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 20 }
    Test={ param($t) Test-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0 } }

  [pscustomobject]@{ Id='gamestask'; Cat='Desempenho & Jogos'; Name='Prioridade alta pra jogos (MMCSS)'; Default=$true; Reboot=$false
    Desc='Agendador multimidia (Tasks\Games): prioridade de CPU/IO alta e GPU 8 pros jogos. Vale pros jogos abertos depois de ativar.'
    Apply={ param($t) $k='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Set-Reg $k 'GPU Priority' 8; Set-Reg $k 'Priority' 6; Set-Reg $k 'Scheduling Category' 'High' 'String'; Set-Reg $k 'SFIO Priority' 'High' 'String' }
    Revert={ param($t) $k='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Set-Reg $k 'GPU Priority' 8; Set-Reg $k 'Priority' 2; Set-Reg $k 'Scheduling Category' 'Medium' 'String'; Set-Reg $k 'SFIO Priority' 'Normal' 'String' }
    Test={ param($t) Test-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' } }

  [pscustomobject]@{ Id='powerthrottle'; Cat='Desempenho & Jogos'; Name='Desligar Power Throttling'; Default=$true; Reboot=$false
    Desc='PowerThrottlingOff=1: impede o Windows de reduzir a CPU dos apps pra economizar energia. Desempenho mais constante.'
    Apply={ param($t) Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
    Revert={ param($t) Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 0 }
    Test={ param($t) Test-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 } }

  [pscustomobject]@{ Id='visualfx'; Cat='Desempenho & Jogos'; Name='Efeitos visuais: desempenho (mantem so a fonte suave)'; Default=$true; Reboot=$false
    Desc='Desliga animacoes, sombras e transparencias do Windows pra deixar o desktop mais leve, mas mantem a suavizacao de fonte (ClearType) pro texto nao ficar serrilhado. Aplica na hora.'
    Apply={ param($t) Set-VisualFX $true }
    Revert={ param($t) Set-VisualFX $false }
    Test={ param($t) Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3 } }
)

# ---- Debloat (apps) - catalogo fiel ao Winhance (Windows Apps) ----
# N=nome  Pkg=pacotes appx (1+)  Rec=recomendado remover  Warn=perigoso (vermelho)  D=descricao
$apps = @(
  # 3D / Realidade Mista
  @{N='3D Viewer';                 Pkg=@('Microsoft.Microsoft3DViewer');                Store='9NBLGGH42THS'; Rec=$true;  D='Visualizador de modelos 3D (glTF, FBX, OBJ).'},
  @{N='Mixed Reality Portal';      Pkg=@('Microsoft.MixedReality.Portal');              Store='9NG1H8B3ZC7M'; Rec=$true;  D='Portal de realidade mista (VR), obsoleto.'},
  # Bing / Busca
  @{N='Bing Search';               Pkg=@('Microsoft.BingSearch');                       Store='9NZBF4GT040C'; Rec=$true;  D='Resultados da web do Bing na busca do Windows.'},
  @{N='Microsoft News';            Pkg=@('Microsoft.BingNews');                         Store='9WZDNCRFHVFW'; Rec=$true;  D='Leitor de notícias do Microsoft Start.'},
  @{N='MSN Weather';               Pkg=@('Microsoft.BingWeather');                      Store='9WZDNCRFJ3Q2'; Rec=$true;  D='App de previsão do tempo.'},
  # Câmera / Mídia
  @{N='Camera';                    Pkg=@('Microsoft.WindowsCamera');                    Store='9WZDNCRFJBBG'; Rec=$false; D='App de câmera. Mantenha se usa webcam.'},
  @{N='Clipchamp';                 Pkg=@('Clipchamp.Clipchamp');                        Store='9P1J8S7CCWWT'; Rec=$true;  D='Editor de vídeo da Microsoft.'},
  # Utilitários
  @{N='Alarms & Clock';            Pkg=@('Microsoft.WindowsAlarms');                    Store='9WZDNCRFJ3PR'; Rec=$false; D='Alarmes, cronômetro e relógio mundial.'},
  @{N='Cortana';                   Pkg=@('Microsoft.549981C3F5F10');                    Store='9NFFX4SZZ23L'; Rec=$true;  D='Assistente de voz Cortana (descontinuada).'},
  @{N='Get Help';                  Pkg=@('Microsoft.GetHelp');                          Store='9PKDZBMV1H3T'; Rec=$true;  D='App de suporte da Microsoft.'},
  @{N='Calculator';                Pkg=@('Microsoft.WindowsCalculator');                Store='9WZDNCRFHVN5'; Rec=$false; D='Calculadora. Recomendo manter.'},
  # Desenvolvimento
  @{N='Windows Advanced Settings'; Pkg=@('Microsoft.Windows.DevHome');                  Store='9N8MHTPHNGVV'; Rec=$true;  D='Painel Dev Home, para desenvolvedores.'},
  # Comunicação
  @{N='Microsoft Family Safety';   Pkg=@('MicrosoftCorporationII.MicrosoftFamily');     Store='9PDJDJS743XF'; Rec=$false; D='Controle parental / família.'},
  @{N='Mail and Calendar';         Pkg=@('microsoft.windowscommunicationsapps');        Store='9WZDNCRFHVQM'; Rec=$false; D='E-mail e Calendário clássicos.'},
  @{N='Skype';                     Pkg=@('Microsoft.SkypeApp');                         Store='9WZDNCRFJ364'; Rec=$true;  D='Skype (descontinuado).'},
  @{N='Microsoft Teams';           Pkg=@('MSTeams','MicrosoftTeams');                   Store='XP8BT8DW290MPQ'; Rec=$true;  D='Teams pessoal, instalado automaticamente.'},
  # Ferramentas do sistema
  @{N='Feedback Hub';              Pkg=@('Microsoft.WindowsFeedbackHub');               Store='9NBLGGH4R32N'; Rec=$true;  D='Envio de feedback para a Microsoft.'},
  @{N='Maps';                      Pkg=@('Microsoft.WindowsMaps');                      Store='9WZDNCRDTBVB'; Rec=$true;  D='Mapas da Microsoft.'},
  @{N='Terminal';                  Pkg=@('Microsoft.WindowsTerminal');                  Store='9N0DX20HK701'; Rec=$false; D='Terminal moderno. Útil, recomendo manter.'},
  # Office
  @{N='MS 365 (Office Hub)';       Pkg=@('Microsoft.MicrosoftOfficeHub');               Store='9WZDNCRD29V9'; Rec=$true;  D='Hub do Microsoft 365 / Office.'},
  @{N='Outlook for Windows';       Pkg=@('Microsoft.OutlookForWindows');                Store='9NRX63209R7B'; Rec=$false; D='Novo Outlook.'},
  @{N='OneNote';                   Pkg=@('Microsoft.Office.OneNote');                   Store='XPFFZHVGQWWLHB'; Rec=$false; D='OneNote (anotações).'},
  # Gráficos
  @{N='Paint 3D';                  Pkg=@('Microsoft.MSPaint');                          Rec=$true;  D='Paint 3D (diferente do Paint clássico).'},
  @{N='Paint';                     Pkg=@('Microsoft.Paint');                            Store='9PCFS5B6T72H'; Rec=$false; D='Paint clássico. Recomendo manter.'},
  @{N='Photos';                    Pkg=@('Microsoft.Windows.Photos');                   Store='9WZDNCRFJBH4'; Rec=$false; D='Visualizador de fotos. Recomendo manter.'},
  @{N='Snipping Tool';             Pkg=@('Microsoft.ScreenSketch');                     Store='9MZ95KL8MR0L'; Rec=$false; D='Ferramenta de captura de tela. Manter.'},
  # Social
  @{N='People';                    Pkg=@('Microsoft.People');                           Store='9NBLGGH10PG8'; Rec=$true;  D='Agenda de contatos.'},
  # Automação
  @{N='Power Automate';            Pkg=@('Microsoft.PowerAutomateDesktop');             Store='9NFTCH6J7FHV'; Rec=$true;  D='Automação de fluxos (desktop).'},
  # Suporte
  @{N='Quick Assist';              Pkg=@('MicrosoftCorporationII.QuickAssist');         Store='9P7BP5VNWKX5'; Rec=$false; D='Assistência remota da Microsoft.'},
  # Jogos
  @{N='Solitaire Collection';      Pkg=@('Microsoft.MicrosoftSolitaireCollection');     Store='9WZDNCRFHWD2'; Rec=$true;  D='Coleção de Paciência (Solitaire).'},
  @{N='Xbox';                      Pkg=@('Microsoft.GamingApp','Microsoft.XboxApp');    Store='9MV0B5HZVK9Z'; Rec=$false; D='App Xbox (jogos e Game Pass).'},
  @{N='Xbox Identity Provider';    Pkg=@('Microsoft.XboxIdentityProvider');             Store='9WZDNCRD1HKW'; Rec=$false; D='Login Xbox em jogos. Remover pode quebrar logins.'},
  @{N='Xbox Game Bar Plugin';      Pkg=@('Microsoft.XboxGameOverlay');                  Store='9NBLGGH537C2'; Rec=$false; D='Plugin da Game Bar.'},
  @{N='Xbox Live In-Game';         Pkg=@('Microsoft.Xbox.TCUI');                        Store='9NKNC0LD5NN6'; Rec=$false; D='Interface Xbox Live dentro dos jogos.'},
  @{N='Xbox Game Bar';             Pkg=@('Microsoft.XboxGamingOverlay');                Store='9NZKPSTSNW4P'; Rec=$false; D='Barra de jogos (overlay). Útil pra gravar.'},
  # Loja
  @{N='Microsoft Store';           Pkg=@('Microsoft.WindowsStore');                     Store='9WZDNCRFJBMP'; Rec=$false; Warn=$true; D='AVISO: remove a Loja. Sem ela fica difícil reinstalar apps.'},
  # Mídia
  @{N='Media Player';              Pkg=@('Microsoft.ZuneMusic');                        Store='9WZDNCRFJ3PT'; Rec=$false; D='Media Player (música / Groove).'},
  @{N='Movies & TV';               Pkg=@('Microsoft.ZuneVideo');                        Store='9WZDNCRFJ3P2'; Rec=$false; D='Filmes e TV (vídeo).'},
  @{N='Sound Recorder';            Pkg=@('Microsoft.WindowsSoundRecorder');             Store='9WZDNCRFHWKN'; Rec=$false; D='Gravador de voz.'},
  # Produtividade
  @{N='Sticky Notes';              Pkg=@('Microsoft.MicrosoftStickyNotes');             Store='9NBLGGH4QGHW'; Rec=$false; D='Notas autoadesivas.'},
  @{N='Tips';                      Pkg=@('Microsoft.Getstarted');                       Rec=$true;  D='Dicas do Windows.'},
  @{N='To Do';                     Pkg=@('Microsoft.Todos');                            Store='9NBLGGH5R558'; Rec=$false; D='Listas e tarefas (Microsoft To Do).'},
  @{N='Notepad';                   Pkg=@('Microsoft.WindowsNotepad');                   Store='9MSMLRH6LZF3'; Rec=$false; D='Bloco de Notas. Recomendo manter.'},
  # Telefone
  @{N='Phone Link';                Pkg=@('Microsoft.YourPhone');                        Store='9NMPJ99VJBWV'; Rec=$false; D='Vincular ao Celular.'},
  # IA
  @{N='Copilot';                   Pkg=@('Microsoft.Copilot','Microsoft.Windows.Ai.Copilot.Provider'); Store='9NHT9RB2F4HD'; Rec=$true; D='Assistente Copilot.'},
  @{N='Windows AI Experience';     Pkg=@('MicrosoftWindows.Client.AIX');                Rec=$false; D='Componente de IA do Windows.'},
  @{N='Windows Copilot Client';    Pkg=@('MicrosoftWindows.Client.CoPilot');            Rec=$false; D='Cliente do Copilot no sistema.'},
  @{N='Edge Game Assist';          Pkg=@('Microsoft.Edge.GameAssist');                  Rec=$false; D='Edge para jogos (overlay).'},
  @{N='Office Actions Server';     Pkg=@('Microsoft.Office.ActionsServer');             Rec=$false; D='Servidor de ações de IA do Office.'},
  @{N='AI Manager';                Pkg=@('aimgr');                                      Rec=$false; D='Gerenciador de IA do Office.'},
  @{N='Writing Assistant';         Pkg=@('Microsoft.WritingAssistant');                 Rec=$false; D='Assistente de escrita por IA.'},
  @{N='AI Workload Packages';      Pkg=@('WindowsWorkload.OnnxRuntimeGenAI','WindowsWorkload.SemanticTextSimilarity','WindowsWorkload.ImageSearch','WindowsWorkload.ContentExtraction','WindowsWorkload.ScreenRegionDetection','WindowsWorkload.TextRecognition','WindowsWorkload.ImageContentModeration','WindowsWorkload.ScreenSemanticsOCR','WindowsWorkload.ImageSuperResolution','WindowsWorkload.ObjectErase','WindowsWorkload.ImageDescriptor','WindowsWorkload.PortraitBlur','WindowsWorkload.TextToSpeech','WindowsWorkload.SpeechToText','WindowsWorkload.ImageSegmentation','WindowsWorkload.CreativeFilter','WindowsWorkload.StudioEffects','WindowsWorkload.SubtitleTranslation','WindowsWorkload.Summarization','WindowsWorkload.RewriteTextSuggestion'); Rec=$false; D='Pacotes de IA local (só existem em PCs Copilot+ com NPU).'},
  @{N='Copilot+ PC AI Packages';   Pkg=@('MicrosoftWindows.Voiess','MicrosoftWindows.Speion','MicrosoftWindows.Livtop','MicrosoftWindows.InpApp','MicrosoftWindows.Filons'); Rec=$false; D='Pacotes de voz/fala/digitação de PCs Copilot+.'},
  # Sistema
  @{N='App Installer (winget)';    Pkg=@('Microsoft.DesktopAppInstaller');              Store='9NBLGGH4NNS1'; Rec=$false; Warn=$true; D='AVISO: remove o winget. Você perde a instalação por linha de comando.'}
)
$debloat = foreach ($a in $apps) {
  [pscustomobject]@{
    Id=('app_'+$a.Pkg[0]); Cat='Apps / Tranqueiras'; Name=$a.N; Default=[bool]$a.Rec; Warn=[bool]$a.Warn; Reboot=$false; Pkg=$a.Pkg; Store=$a.Store; Invert=$true
    Desc=$a.D
    Apply={ param($t)
        foreach ($p in $t.Pkg) {
            # desprovisiona ANTES de remover (critico no Win10: senao Remove-AppxPackage -AllUsers falha com 0x80070002)
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $p } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            Get-AppxPackage -Name $p -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        } }
    Revert={ param($t)
        $done = $false
        foreach ($p in $t.Pkg) {
            $pk = Get-AppxPackage -Name $p -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation } | Select-Object -First 1
            if ($pk) { Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $pk.InstallLocation 'AppXManifest.xml') -ErrorAction SilentlyContinue; $done = $true }
        }
        if ($done) { return }
        if ($t.Store) {
            if (Test-Winget) {
                Start-Process -FilePath winget -ArgumentList @('install','--id',$t.Store,'--source','msstore','--accept-package-agreements','--accept-source-agreements','--silent') -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                return
            }
            throw 'Reinstale pela Microsoft Store (winget nao encontrado).'
        }
        throw 'Removido do sistema - reinstale pela Microsoft Store.' }
    Test={ param($t) -not [bool]($t.Pkg | Where-Object { $script:Installed.ContainsKey($_) }) }
  }
}

# ---- Limpeza ----
$cleanup = @(
  [pscustomobject]@{ Id='temp'; Cat='Limpeza'; Name='Limpar arquivos temporários'; Default=$true; Reboot=$false
    Desc='Apaga %TEMP% e C:\Windows\Temp. Ação não reversível (mas segura).'
    Apply={ param($t) foreach($d in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'))){ Get-ChildItem -Path $d -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } }
    Revert={ param($t) throw 'Limpeza não tem reversão.' }
    Test={ param($t) $false } }
  [pscustomobject]@{ Id='dns'; Cat='Limpeza'; Name='Limpar cache de DNS'; Default=$true; Reboot=$false
    Desc='Executa ipconfig /flushdns.'
    Apply={ param($t) ipconfig /flushdns | Out-Null }
    Revert={ param($t) throw 'Limpeza não tem reversão.' }
    Test={ param($t) $false } }
  [pscustomobject]@{ Id='recycle'; Cat='Limpeza'; Name='Esvaziar Lixeira'; Default=$false; Reboot=$false
    Desc='Esvazia a Lixeira de todos os drives. Ação não reversível.'
    Apply={ param($t) Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
    Revert={ param($t) throw 'Limpeza não tem reversão.' }
    Test={ param($t) $false } }
)

# ---- Apps especiais: OneDrive / Edge ----
$advanced = @(
  [pscustomobject]@{ Id='onedrive_remove'; Cat='Apps / Tranqueiras'; Name='OneDrive'; Default=$false; Reboot=$false; Invert=$true
    Desc='Roda o desinstalador oficial e limpa resíduos (ícone do Explorer, tarefas, startup, perfil padrão). Seus arquivos em %USERPROFILE%\OneDrive são preservados. Reversível: reinstala.'
    Apply={ param($t)
        Stop-Process -Name 'OneDrive','OneDriveSetup','FileCoAuth' -Force -ErrorAction SilentlyContinue
        $us = (Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe' -ErrorAction SilentlyContinue).UninstallString
        if (-not $us) { $us = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe' -ErrorAction SilentlyContinue).UninstallString }
        if ($us) { Start-Process -FilePath cmd.exe -ArgumentList "/c $us" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue }
        else {
            $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe","$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($setup) { Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue }
        }
        Get-AppxPackage -AllUsers '*OneDriveSync*' -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Set-Reg 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
        Set-Reg 'HKCU:\Software\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
        Remove-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDrive'
        Get-ScheduledTask -TaskName '*OneDrive*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk" -Force -ErrorAction SilentlyContinue
        reg.exe load 'HKU\BoostDefault' "$env:SystemDrive\Users\Default\NTUSER.DAT" 2>$null | Out-Null
        reg.exe delete 'HKU\BoostDefault\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' /v 'OneDriveSetup' /f 2>$null | Out-Null
        reg.exe unload 'HKU\BoostDefault' 2>$null | Out-Null }
    Revert={ param($t)
        Set-Reg 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 1
        Set-Reg 'HKCU:\Software\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 1
        $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe","$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($setup) { Start-Process -FilePath $setup -ErrorAction SilentlyContinue } else { throw 'OneDriveSetup.exe não encontrado - baixe o OneDrive em microsoft.com.' } }
    Test={ param($t) -not (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") } }

  [pscustomobject]@{ Id='edge_remove'; Cat='Apps / Tranqueiras'; Name='Microsoft Edge (avançado)'; Default=$false; Warn=$true; Reboot=$false; Invert=$true
    Desc='AVISO: a Microsoft não suporta remover o Edge. Desinstalador oficial (--force-uninstall), PRESERVA o WebView2, mata o EdgeUpdate e instala o redirecionamento OpenWebSearch (AveYo): links microsoft-edge: abrem no seu navegador padrão. Tenha outro navegador instalado. Pode voltar em feature updates grandes.'
    Apply={ param($t)
        Stop-Process -Name 'msedge','MicrosoftEdgeUpdate' -Force -ErrorAction SilentlyContinue
        $owsDir = "$env:ProgramData\SoftProjetos\OpenWebSearch"
        New-Item -ItemType Directory -Path $owsDir -Force -ErrorAction SilentlyContinue | Out-Null
        $stub = "$owsDir\ie_to_edge_stub.exe"
        if (-not (Test-Path $stub)) {
            $src = $null
            foreach ($base in @("${env:ProgramFiles(x86)}\Microsoft\Edge","$env:ProgramFiles\Microsoft\Edge")) {
                if (Test-Path $base) { $src = Get-ChildItem $base -Filter 'ie_to_edge_stub.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 }
                if ($src) { break }
            }
            if (-not $src) { foreach ($p in @("$env:ProgramData\ie_to_edge_stub.exe","$env:Public\ie_to_edge_stub.exe")) { if (Test-Path $p) { $src = Get-Item $p; break } } }
            if ($src) { Copy-Item $src.FullName $stub -Force -ErrorAction SilentlyContinue }
        }
        $owsCore = @'
@title OpenWebSearch 2023 & echo off & set ?= open start menu web search, widgets links or help in your chosen browser - by AveYo
for /f %%E in ('"prompt $E$S& for %%e in (1) do rem"') do echo;%%E[2t 2>nul & rem AveYo: minimize prompt
call :reg_var "HKCU\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice" ProgID ProgID
if /i "%ProgID%" equ "MSEdgeHTM" echo;Default browser is set to Edge! Change it or remove OpenWebSearch script. & pause & exit /b
call :reg_var "HKCR\%ProgID%\shell\open\command" "" Browser
set Choice=& for %%. in (%Browser%) do if not defined Choice set "Choice=%%~."
call :reg_var "HKCR\MSEdgeMHT\shell\open\command" "" FallBack
set "Edge=" & for %%. in (%FallBack%) do if not defined Edge set "Edge=%%~."
set "URI=" & set "URL=" & set "NOOP=" & set "PassTrough=%Edge:msedge=edge%"
set "CLI=%CMDCMDLINE:"=``% "
if defined CLI set "CLI=%CLI:*ie_to_edge_stub.exe`` =%"
if defined CLI set "CLI=%CLI:*ie_to_edge_stub.exe =%"
if defined CLI set "CLI=%CLI:*msedge.exe`` =%"
if defined CLI set "CLI=%CLI:*msedge.exe =%"
set "FIX=%CLI:~-1%"
if defined CLI if "%FIX%"==" " set "CLI=%CLI:~0,-1%"
if defined CLI set "RED=%CLI:microsoft-edge=%"
if defined CLI set "URL=%CLI:http=%"
if defined CLI set "ARG=%CLI:``="%"
if "%CLI%" equ "%RED%" (set NOOP=1) else if "%CLI%" equ "%URL%" (set NOOP=1)
if defined NOOP if not exist "%PassTrough%" echo;@mklink /h "%PassTrough%" "%Edge%" >"%Temp%\OpenWebSearchRepair.cmd"
if defined NOOP if not exist "%PassTrough%" schtasks /run /tn OpenWebSearchRepair 2>nul >nul
if defined NOOP if not exist "%PassTrough%" timeout /t 3 >nul
if defined NOOP if exist "%PassTrough%" start "" "%PassTrough%" %ARG%
if defined NOOP exit /b
set "URL=%CLI:*microsoft-edge=%"
set "URL=http%URL:*http=%"
set "FIX=%URL:~-2%"
if defined URL if "%FIX%"=="``" set "URL=%URL:~0,-2%"
call :dec_url
start "" "%Choice%" "%URL%"
exit

:reg_var [USAGE] call :reg_var "HKCU\Volatile Environment" value-or-"" variable [extra options]
set {var}=& set {reg}=reg query "%~1" /v %2 /z /se "," /f /e& if %2=="" set {reg}=reg query "%~1" /ve /z /se "," /f /e
for /f "skip=2 tokens=* delims=" %%V in ('%{reg}% %4 %5 %6 %7 %8 %9 2^>nul') do if not defined {var} set "{var}=%%V"
if not defined {var} (set {reg}=& set "%~3="& exit /b) else if %2=="" set "{var}=%{var}:*)    =%"& rem AveYo: v3
if not defined {var} (set {reg}=& set "%~3="& exit /b) else set {reg}=& set "%~3=%{var}:*)    =%"& set {var}=& exit /b

:dec_url brute url percent decoding by AveYo
set ".=%URL:!=}%"&setlocal enabledelayedexpansion& rem brute url percent decoding
set ".=!.:%%={!" &set ".=!.:{3A=:!" &set ".=!.:{2F=/!" &set ".=!.:{3F=?!" &set ".=!.:{23=#!" &set ".=!.:{5B=[!" &set ".=!.:{5D=]!"
set ".=!.:{40=@!"&set ".=!.:{21=}!" &set ".=!.:{24=$!" &set ".=!.:{26=&!" &set ".=!.:{27='!" &set ".=!.:{28=(!" &set ".=!.:{29=)!"
set ".=!.:{2A=*!"&set ".=!.:{2B=+!" &set ".=!.:{2C=,!" &set ".=!.:{3B=;!" &set ".=!.:{3D==!" &set ".=!.:{25=%%!"&set ".=!.:{20= !"
set ".=!.:{=%%!" &rem set ",=!.:%%=!" & if "!,!" neq "!.!" endlocal& set "URL=%.:}=!%" & call :dec_url
endlocal& set "URL=%.:}=!%" & exit /b
rem done
'@
        $owsCore | Out-File -FilePath "$owsDir\OpenWebSearch.cmd" -Encoding ASCII -Force -ErrorAction SilentlyContinue
        if (Test-Path $stub) {
            $reME = 'Registry::HKEY_CLASSES_ROOT\microsoft-edge'
            New-Item -Path $reME -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $reME -Name '(default)' -Value 'URL:microsoft-edge' -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $reME -Name 'URL Protocol' -Value '' -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $reME -Name 'NoOpenWith' -Value '' -ErrorAction SilentlyContinue
            foreach ($k in @("$reME\shell\open\command",'Registry::HKEY_CLASSES_ROOT\MSEdgeHTM\shell\open\command')) {
                New-Item -Path $k -Force -ErrorAction SilentlyContinue | Out-Null
                Set-ItemProperty -Path $k -Name '(default)' -Value ('"' + $stub + '" %1') -ErrorAction SilentlyContinue
            }
            $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
            New-Item -Path "$ifeo\ie_to_edge_stub.exe" -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path "$ifeo\ie_to_edge_stub.exe" -Name 'UseFilter' -Value 1 -Type DWord -ErrorAction SilentlyContinue
            New-Item -Path "$ifeo\ie_to_edge_stub.exe\0" -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path "$ifeo\ie_to_edge_stub.exe\0" -Name 'FilterFullPath' -Value $stub -ErrorAction SilentlyContinue
            $flags = if ([Environment]::OSVersion.Version.Build -gt 25179) { '--width 1 --height 1' } else { '--headless' }
            Set-ItemProperty -Path "$ifeo\ie_to_edge_stub.exe\0" -Name 'Debugger' -Value ("$env:SystemRoot\system32\conhost.exe $flags $owsDir\OpenWebSearch.cmd") -ErrorAction SilentlyContinue
            Remove-Item -Path "$ifeo\msedge.exe" -Recurse -Force -ErrorAction SilentlyContinue
            $rep = @'
$stub = 'C:\ProgramData\SoftProjetos\OpenWebSearch\ie_to_edge_stub.exe'
if (Test-Path $stub) {
    $cmdval = '"' + $stub + '" %1'
    foreach ($k in @('Registry::HKEY_CLASSES_ROOT\microsoft-edge\shell\open\command','Registry::HKEY_CLASSES_ROOT\MSEdgeHTM\shell\open\command')) {
        $cur = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).'(default)'
        if (-not $cur -or $cur -notlike '*ie_to_edge_stub*') {
            New-Item -Path $k -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $k -Name '(default)' -Value $cmdval -ErrorAction SilentlyContinue
        }
    }
}
'@
            $rep | Out-File -FilePath "$owsDir\OpenWebSearchRepair.ps1" -Encoding UTF8 -Force -ErrorAction SilentlyContinue
            try {
                $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$owsDir\OpenWebSearchRepair.ps1`"")
                $tr = New-ScheduledTaskTrigger -AtLogon
                $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
                $pr = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
                Register-ScheduledTask -TaskName 'OpenWebSearchRepair' -Action $a -Trigger $tr -Settings $set -Principal $pr -Force -ErrorAction SilentlyContinue | Out-Null
            } catch {}
        }
        $us = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge' -ErrorAction SilentlyContinue).UninstallString
        if (-not $us) { $us = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge' -ErrorAction SilentlyContinue).UninstallString }
        if (-not $us) { throw 'Edge não encontrado (talvez já removido).' }
        Start-Process -FilePath cmd.exe -ArgumentList "/c $us --force-uninstall --silent" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1
        Set-Reg 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1
        foreach ($svc in 'edgeupdate','edgeupdatem') { Start-Process -FilePath sc.exe -ArgumentList "delete $svc" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue }
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like '*MicrosoftEdgeUpdate*' } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue }
    Revert={ param($t)
        $owsDir = "$env:ProgramData\SoftProjetos\OpenWebSearch"
        Unregister-ScheduledTask -TaskName 'OpenWebSearchRepair' -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path 'Registry::HKEY_CLASSES_ROOT\microsoft-edge' -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path 'Registry::HKEY_CLASSES_ROOT\MSEdgeHTM\shell\open\command' -Recurse -Force -ErrorAction SilentlyContinue
        $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
        Remove-Item -Path "$ifeo\ie_to_edge_stub.exe" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $owsDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Reg 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium'
        Remove-Reg 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium'
        if (Test-Winget) {
            Start-Process -FilePath winget -ArgumentList @('install','--id','Microsoft.Edge','--accept-package-agreements','--accept-source-agreements','--silent') -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        } else { throw 'Edge: redirecionamento removido. Reinstale em microsoft.com/edge (winget nao encontrado).' } }
    Test={ param($t) -not (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") } }
)

$script:Tweaks = @($reg) + @($debloat) + @($cleanup) + @($advanced)

# ---- Catalogo de programas externos (winget) — fiel ao Winhance ----
$externalApps = @(
  @{N='Microsoft EdgeWebView'; G='Browsers'; W='Microsoft.EdgeWebView2Runtime'}
  @{N='Thorium'; G='Browsers'; W='Alex313031.Thorium'}
  @{N='Mercury'; G='Browsers'; W='Alex313031.Mercury'}
  @{N='Mozilla Firefox'; G='Browsers'; W='Mozilla.Firefox'}
  @{N='Google Chrome'; G='Browsers'; W='Google.Chrome'}
  @{N='ungoogled-chromium'; G='Browsers'; W='Eloston.Ungoogled-Chromium'}
  @{N='Brave'; G='Browsers'; W='Brave.Brave'}
  @{N='Opera'; G='Browsers'; W='Opera.Opera'}
  @{N='Opera GX'; G='Browsers'; W='Opera.OperaGX'}
  @{N='Arc Browser'; G='Browsers'; W='TheBrowserCompany.Arc'}
  @{N='Tor Browser'; G='Browsers'; W='TorProject.TorBrowser'}
  @{N='Vivaldi'; G='Browsers'; W='Vivaldi.Vivaldi'}
  @{N='Waterfox'; G='Browsers'; W='Waterfox.Waterfox'}
  @{N='Zen Browser'; G='Browsers'; W='Zen-Team.Zen-Browser'}
  @{N='Mullvad Browser'; G='Browsers'; W='MullvadVPN.MullvadBrowser'}
  @{N='Pale Moon Browser'; G='Browsers'; W='MoonchildProductions.PaleMoon'}
  @{N='Maxthon'; G='Browsers'; W='Maxthon.Maxthon'}
  @{N='Ablaze Floorp'; G='Browsers'; W='Ablaze.Floorp'}
  @{N='DuckDuckGo'; G='Browsers'; W='DuckDuckGo.DesktopBrowser'}
  @{N='LibreWolf'; G='Browsers'; W='LibreWolf.LibreWolf'}
  @{N='7-Zip'; G='Compression'; W='7zip.7zip'}
  @{N='WinRAR archiver'; G='Compression'; W='RARLab.WinRAR'}
  @{N='PeaZip'; G='Compression'; W='Giorgiotani.Peazip'}
  @{N='NanaZip'; G='Compression'; W='M2Team.NanaZip'}
  @{N='Nilesoft Shell'; G='Customization Utilities'; W='Nilesoft.Shell'}
  @{N='StartAllBack (Win 11)'; G='Customization Utilities'; W='StartIsBack.StartAllBack'}
  @{N='StartIsBack++ (Win 10)'; G='Customization Utilities'; W='StartIsBack.StartIsBack'}
  @{N='Open-Shell'; G='Customization Utilities'; W='Open-Shell.Open-Shell-Menu'}
  @{N='Windhawk'; G='Customization Utilities'; W='RamenSoftware.Windhawk'}
  @{N='Lively Wallpaper'; G='Customization Utilities'; W='rocksdanister.LivelyWallpaper'}
  @{N='Sucrose Wallpaper Engine'; G='Customization Utilities'; W='Taiizor.SucroseWallpaperEngine'}
  @{N='Rainmeter'; G='Customization Utilities'; W='Rainmeter.Rainmeter'}
  @{N='ExplorerPatcher'; G='Customization Utilities'; W='valinet.ExplorerPatcher'}
  @{N='John''s Background Switcher'; G='Customization Utilities'; W='johnsadventures.JohnsBackgroundSwitcher'}
  @{N='Microsoft PowerToys'; G='Customization Utilities'; W='Microsoft.PowerToys'}
  @{N='Nexus'; G='Customization Utilities'; W='WinStep.Nexus'}
  @{N='AutoHotkey v2'; G='Customization Utilities'; W='AutoHotkey.AutoHotkey'}
  @{N='Python 3.13'; G='Development Apps'; W='Python.Python.3.13'}
  @{N='Notepad++'; G='Development Apps'; W='Notepad++.Notepad++'}
  @{N='WinSCP'; G='Development Apps'; W='WinSCP.WinSCP'}
  @{N='PuTTY'; G='Development Apps'; W='PuTTY.PuTTY'}
  @{N='WinMerge'; G='Development Apps'; W='WinMerge.WinMerge'}
  @{N='Eclipse IDE for Java'; G='Development Apps'; W='EclipseFoundation.Eclipse.Java'}
  @{N='Microsoft Visual Studio Code'; G='Development Apps'; W='Microsoft.VisualStudioCode'}
  @{N='Git'; G='Development Apps'; W='Git.Git'}
  @{N='GitHub Desktop'; G='Development Apps'; W='GitHub.GitHubDesktop'}
  @{N='Meld'; G='Development Apps'; W='Meld.Meld'}
  @{N='LibreOffice'; G='Document Viewers'; W='TheDocumentFoundation.LibreOffice'}
  @{N='ONLYOFFICE Desktop Editors'; G='Document Viewers'; W='ONLYOFFICE.DesktopEditors'}
  @{N='PDFgear'; G='Document Viewers'; W='PDFgear.PDFgear'}
  @{N='SumatraPDF'; G='Document Viewers'; W='SumatraPDF.SumatraPDF'}
  @{N='OpenOffice'; G='Document Viewers'; W='Apache.OpenOffice'}
  @{N='Evernote'; G='Document Viewers'; W='Evernote.Evernote'}
  @{N='CherryTree'; G='Document Viewers'; W='Giuspen.Cherrytree'}
  @{N='Okular'; G='Document Viewers'; W='KDE.Okular'}
  @{N='PDF24 Creator'; G='Document Viewers'; W='geeksoftwareGmbH.PDF24Creator'}
  @{N='Microsoft 365'; G='Document Viewers'; W='Microsoft.Office'}
  @{N='WinDirStat'; G='File & Disk Management'; W='WinDirStat.WinDirStat'}
  @{N='WizTree'; G='File & Disk Management'; W='AntibodySoftware.WizTree'}
  @{N='TreeSize Free'; G='File & Disk Management'; W='JAMSoftware.TreeSize.Free'}
  @{N='Everything'; G='File & Disk Management'; W='voidtools.Everything'}
  @{N='TeraCopy'; G='File & Disk Management'; W='CodeSector.TeraCopy'}
  @{N='File Converter'; G='File & Disk Management'; W='AdrienAllard.FileConverter'}
  @{N='Crystal Disk Info'; G='File & Disk Management'; W='WsSolInfor.CrystalDiskInfo'}
  @{N='Bulk Rename Utility'; G='File & Disk Management'; W='TGRMNSoftware.BulkRenameUtility'}
  @{N='IObit Unlocker'; G='File & Disk Management'; W='IObit.IObitUnlocker'}
  @{N='HiBit Uninstaller'; G='File & Disk Management'; W='HiBitSoftware.HiBitUninstaller'}
  @{N='SanDisk Dashboard'; G='File & Disk Management'; W='SanDisk.Dashboard'}
  @{N='Rufus'; G='File & Disk Management'; W='Rufus.Rufus'}
  @{N='Advanced Renamer'; G='File & Disk Management'; W='HulubuluSoftware.AdvancedRenamer'}
  @{N='Ventoy'; G='File & Disk Management'; W='Ventoy.Ventoy'}
  @{N='Steam'; G='Gaming'; W='Valve.Steam'}
  @{N='Epic Games Launcher'; G='Gaming'; W='EpicGames.EpicGamesLauncher'}
  @{N='GOG GALAXY'; G='Gaming'; W='GOG.Galaxy'}
  @{N='Playnite'; G='Gaming'; W='Playnite.Playnite'}
  @{N='IrfanView64'; G='Imaging'; W='IrfanSkiljan.IrfanView'}
  @{N='Krita'; G='Imaging'; W='KDE.Krita'}
  @{N='Blender'; G='Imaging'; W='BlenderFoundation.Blender'}
  @{N='Paint.NET'; G='Imaging'; W='dotPDN.PaintDotNet'}
  @{N='GIMP'; G='Imaging'; W='GIMP.GIMP.3'}
  @{N='XnViewMP'; G='Imaging'; W='XnSoft.XnViewMP'}
  @{N='XnView'; G='Imaging'; W='XnSoft.XnView.Classic'}
  @{N='Inkscape'; G='Imaging'; W='Inkscape.Inkscape'}
  @{N='Greenshot'; G='Imaging'; W='Greenshot.Greenshot'}
  @{N='ShareX'; G='Imaging'; W='ShareX.ShareX'}
  @{N='Flameshot'; G='Imaging'; W='Flameshot.Flameshot'}
  @{N='FastStone Image Viewer'; G='Imaging'; W='FastStone.Viewer'}
  @{N='ImageGlass'; G='Imaging'; W='DuongDieuPhap.ImageGlass'}
  @{N='Telegram Desktop'; G='Messaging, Email & Calendar'; W='Telegram.TelegramDesktop'}
  @{N='Zoom Workplace'; G='Messaging, Email & Calendar'; W='Zoom.Zoom'}
  @{N='Discord'; G='Messaging, Email & Calendar'; W='Discord.Discord'}
  @{N='Pidgin'; G='Messaging, Email & Calendar'; W='Pidgin.Pidgin'}
  @{N='Mozilla Thunderbird'; G='Messaging, Email & Calendar'; W='Mozilla.Thunderbird'}
  @{N='eM Client'; G='Messaging, Email & Calendar'; W='eMClient.eMClient'}
  @{N='Proton Mail'; G='Messaging, Email & Calendar'; W='Proton.ProtonMail'}
  @{N='Trillian'; G='Messaging, Email & Calendar'; W='CeruleanStudios.Trillian'}
  @{N='Element'; G='Messaging, Email & Calendar'; W='Element.Element'}
  @{N='VLC media player'; G='Multimedia (Audio & Video)'; W='VideoLAN.VLC'}
  @{N='iTunes'; G='Multimedia (Audio & Video)'; W='Apple.iTunes'}
  @{N='AIMP'; G='Multimedia (Audio & Video)'; W='AIMP.AIMP'}
  @{N='foobar2000'; G='Multimedia (Audio & Video)'; W='PeterPawlowski.foobar2000'}
  @{N='Audacity'; G='Multimedia (Audio & Video)'; W='Audacity.Audacity'}
  @{N='GOM Player'; G='Multimedia (Audio & Video)'; W='GOMLab.GOMPlayer'}
  @{N='Spotify'; G='Multimedia (Audio & Video)'; W='Spotify.Spotify'}
  @{N='MediaMonkey'; G='Multimedia (Audio & Video)'; W='VentisMedia.MediaMonkey.5'}
  @{N='HandBrake'; G='Multimedia (Audio & Video)'; W='HandBrake.HandBrake'}
  @{N='OBS Studio'; G='Multimedia (Audio & Video)'; W='OBSProject.OBSStudio'}
  @{N='MPC-BE'; G='Multimedia (Audio & Video)'; W='MPC-BE.MPC-BE'}
  @{N='K-Lite Codec Pack (Mega)'; G='Multimedia (Audio & Video)'; W='CodecGuide.K-LiteCodecPack.Mega'}
  @{N='CapCut'; G='Multimedia (Audio & Video)'; W='ByteDance.CapCut'}
  @{N='PotPlayer64'; G='Multimedia (Audio & Video)'; W='Daum.PotPlayer'}
  @{N='kdenlive'; G='Multimedia (Audio & Video)'; W='KDE.Kdenlive'}
  @{N='MediaInfo'; G='Multimedia (Audio & Video)'; W='MediaArea.MediaInfo.GUI'}
  @{N='SMPlayer'; G='Multimedia (Audio & Video)'; W='SMPlayer.SMPlayer'}
  @{N='Shotcut'; G='Multimedia (Audio & Video)'; W='Meltytech.Shotcut'}
  @{N='LosslessCut'; G='Multimedia (Audio & Video)'; W='ch.LosslessCut'}
  @{N='FxSound'; G='Multimedia (Audio & Video)'; W='FxSound.FxSound'}
  @{N='Volume2'; G='Multimedia (Audio & Video)'; W='irzyxa.Volume2Portable'}
  @{N='Google Drive'; G='Online Storage & Backup'; W='Google.GoogleDrive'}
  @{N='Dropbox'; G='Online Storage & Backup'; W='Dropbox.Dropbox'}
  @{N='SugarSync'; G='Online Storage & Backup'; W='IPVanish.SugarSync'}
  @{N='Nextcloud'; G='Online Storage & Backup'; W='Nextcloud.NextcloudDesktop'}
  @{N='Proton Drive'; G='Online Storage & Backup'; W='Proton.ProtonDrive'}
  @{N='Hekasoft Backup & Restore'; G='Online Storage & Backup'; W='Hekasoft.Backup-Restore'}
  @{N='ImgBurn'; G='Optical Disc Tools'; W='LIGHTNINGUK.ImgBurn'}
  @{N='AnyBurn'; G='Optical Disc Tools'; W='PowerSoftware.AnyBurn'}
  @{N='MakeMKV'; G='Optical Disc Tools'; W='GuinpinSoft.MakeMKV'}
  @{N='CCleaner'; G='Other Utilities'; W='Piriform.CCleaner'}
  @{N='Snappy Driver Installer Origin'; G='Other Utilities'; W='GlennDelahoy.SnappyDriverInstallerOrigin'}
  @{N='Wise Disk Cleaner'; G='Other Utilities'; W='WiseCleaner.WiseDiskCleaner'}
  @{N='Wise Registry Cleaner'; G='Other Utilities'; W='WiseCleaner.WiseRegistryCleaner'}
  @{N='UniGetUI'; G='Other Utilities'; W='MartiCliment.UniGetUI'}
  @{N='OpenRGB'; G='Other Utilities'; W='OpenRGB.OpenRGB'}
  @{N='OpenAudible'; G='Other Utilities'; W='OpenAudible.OpenAudible'}
  @{N='NAPS2'; G='Other Utilities'; W='Cyanfish.NAPS2'}
  @{N='IObit Uninstaller'; G='Other Utilities'; W='IObit.Uninstaller'}
  @{N='Revo Uninstaller'; G='Other Utilities'; W='RevoUninstaller.RevoUninstaller'}
  @{N='Oracle VirtualBox'; G='Other Utilities'; W='Oracle.VirtualBox'}
  @{N='Malwarebytes'; G='Privacy & Security'; W='Malwarebytes.Malwarebytes'}
  @{N='Malwarebytes AdwCleaner'; G='Privacy & Security'; W='Malwarebytes.AdwCleaner'}
  @{N='Windows Firewall Control'; G='Privacy & Security'; W='BiniSoft.WindowsFirewallControl'}
  @{N='OnionShare'; G='Privacy & Security'; W='OnionShare.OnionShare'}
  @{N='O&O ShutUp10++'; G='Privacy & Security'; W='OO-Software.ShutUp10'}
  @{N='RustDesk'; G='Remote Access'; W='RustDesk.RustDesk'}
  @{N='AnyDesk'; G='Remote Access'; W='AnyDesk.AnyDesk'}
  @{N='TeamViewer'; G='Remote Access'; W='TeamViewer.TeamViewer'}
  @{N='UltraViewer'; G='Remote Access'; W='DucFabulous.UltraViewer'}
  @{N='RealVNC Server'; G='Remote Access'; W='RealVNC.VNCServer'}
  @{N='RealVNC Viewer'; G='Remote Access'; W='RealVNC.VNCViewer'}
  @{N='Chrome Remote Desktop'; G='Remote Access'; W='Google.ChromeRemoteDesktopHost'}
  @{N='Parsec'; G='Remote Access'; W='Parsec.Parsec'}
  @{N='Parsec Virtual Display Driver'; G='Remote Access'; W='Parsec.ParsecVDD'}
  @{N='Parsec Virtual USB Driver'; G='Remote Access'; W='Parsec.ParsecVUD'}
  @{N='InputLeap'; G='Remote Access'; W='input-leap.input-leap'}
  @{N='Deskflow'; G='Remote Access'; W='Deskflow.Deskflow'}
  @{N='Microsoft .NET Runtime 3.1'; G='Runtimes & Dependencies'; W='Microsoft.DotNet.Runtime.3_1'}
  @{N='Microsoft .NET Runtime 5.0'; G='Runtimes & Dependencies'; W='Microsoft.DotNet.Runtime.5'}
  @{N='Microsoft .NET Runtime 6.0'; G='Runtimes & Dependencies'; W='Microsoft.DotNet.Runtime.6'}
  @{N='Microsoft .NET Runtime 7.0'; G='Runtimes & Dependencies'; W='Microsoft.DotNet.Runtime.7'}
  @{N='Microsoft .NET Runtime 8.0'; G='Runtimes & Dependencies'; W='Microsoft.DotNet.Runtime.8'}
  @{N='.NET Framework 4.8.1'; G='Runtimes & Dependencies'; W='Microsoft.DotNet.Framework.DeveloperPack_4'}
  @{N='DirectX Runtime'; G='Runtimes & Dependencies'; W='Microsoft.DirectX'}
  @{N='Java Runtime Environment'; G='Runtimes & Dependencies'; W='Oracle.JavaRuntimeEnvironment'}
  @{N='Visual C++ 2005 (x86)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2005.x86'}
  @{N='Visual C++ 2005 (x64)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2005.x64'}
  @{N='Visual C++ 2008 (x86)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2008.x86'}
  @{N='Visual C++ 2008 (x64)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2008.x64'}
  @{N='Visual C++ 2010 (x86)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2010.x86'}
  @{N='Visual C++ 2010 (x64)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2010.x64'}
  @{N='Visual C++ 2012 (x86)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2012.x86'}
  @{N='Visual C++ 2012 (x64)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2012.x64'}
  @{N='Visual C++ 2013 (x86)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2013.x86'}
  @{N='Visual C++ 2013 (x64)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2013.x64'}
  @{N='Visual C++ 2015-2022 (x86)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2015+.x86'}
  @{N='Visual C++ 2015-2022 (x64)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2015+.x64'}
  @{N='Visual C++ 2022 (ARM64)'; G='Runtimes & Dependencies'; W='Microsoft.VCRedist.2015+.arm64'}
)

# =====================================================================
#  UI (WPF) - tema hacker/gamer, navegação por modos
# =====================================================================
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Soft Projetos - Boost" Height="780" Width="950"
        WindowStartupLocation="CenterScreen" Background="#06090D" FontFamily="Consolas, Cascadia Mono, Lucida Console">
  <Window.Resources>
    <Style x:Key="Nav" TargetType="Button">
      <Setter Property="Background" Value="#00000000"/>
      <Setter Property="Foreground" Value="#7E8C99"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height" Value="44"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Padding" Value="20,0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Accent" TargetType="Button">
      <Setter Property="Background" Value="#36F9A6"/>
      <Setter Property="Foreground" Value="#04130C"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,11"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#62FFC4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Background" Value="#00000000"/>
      <Setter Property="Foreground" Value="#8CA0AD"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="Margin" Value="4,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="#21303C" BorderThickness="1" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="BorderBrush" Value="#36F9A6"/>
                <Setter Property="Foreground" Value="#36F9A6"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#CBD8E2"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="#00000000">
              <Border x:Name="box" Width="17" Height="17" CornerRadius="3" BorderBrush="#34424E" BorderThickness="1.5" Background="#0A1118" VerticalAlignment="Center">
                <TextBlock x:Name="chk" Text="&#10003;" Foreground="#04130C" FontSize="12" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="#36F9A6"/>
                <Setter TargetName="box" Property="BorderBrush" Value="#36F9A6"/>
                <Setter TargetName="chk" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="#36F9A6"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Switch" TargetType="ToggleButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Width" Value="50"/>
      <Setter Property="Height" Value="24"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid>
              <Border x:Name="trk" CornerRadius="12" Background="#2A1216" BorderBrush="#FF7088" BorderThickness="1.2"/>
              <TextBlock x:Name="lblOff" Text="OFF" Foreground="#FF7088" FontFamily="Consolas" FontSize="8" FontWeight="Bold" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,7,0"/>
              <TextBlock x:Name="lblOn" Text="ON" Foreground="#04130C" FontFamily="Consolas" FontSize="8" FontWeight="Bold" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="8,0,0,0" Visibility="Collapsed"/>
              <Border x:Name="knob" Width="18" Height="18" CornerRadius="9" Background="#FF7088" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="3,0,0,0">
                <Border.Effect>
                  <DropShadowEffect Color="#000000" BlurRadius="4" ShadowDepth="1" Opacity="0.5"/>
                </Border.Effect>
                <Border.RenderTransform>
                  <TranslateTransform x:Name="kx" X="0"/>
                </Border.RenderTransform>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="trk" Property="Background" Value="#0F3D24"/>
                <Setter TargetName="trk" Property="BorderBrush" Value="#36F9A6"/>
                <Setter TargetName="knob" Property="Background" Value="#36F9A6"/>
                <Setter TargetName="knob" Property="Effect">
                  <Setter.Value>
                    <DropShadowEffect Color="#36F9A6" BlurRadius="9" ShadowDepth="0" Opacity="0.85"/>
                  </Setter.Value>
                </Setter>
                <Setter TargetName="lblOff" Property="Visibility" Value="Collapsed"/>
                <Setter TargetName="lblOn" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="16"/>
      <Setter Property="Background" Value="#0A1118"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="{TemplateBinding Background}">
              <Grid.RowDefinitions>
                <RowDefinition Height="16"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="16"/>
              </Grid.RowDefinitions>
              <RepeatButton Grid.Row="0" Command="ScrollBar.LineUpCommand" Focusable="False" IsTabStop="False">
                <RepeatButton.Template>
                  <ControlTemplate TargetType="RepeatButton">
                    <Border x:Name="bu" Background="Transparent">
                      <Path x:Name="au" Data="M 5 0 L 10 6 L 0 6 Z" Fill="#5A6A75" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="bu" Property="Background" Value="#13202B"/>
                        <Setter TargetName="au" Property="Fill" Value="#36F9A6"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </RepeatButton.Template>
              </RepeatButton>
              <Track Grid.Row="1" x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Focusable="False" IsTabStop="False">
                    <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb MinHeight="18">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border x:Name="th" CornerRadius="5" Background="#46586A" Margin="3,3"/>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="th" Property="Background" Value="#36F9A6"/></Trigger>
                          <Trigger Property="IsDragging" Value="True"><Setter TargetName="th" Property="Background" Value="#36F9A6"/></Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Focusable="False" IsTabStop="False">
                    <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
              </Track>
              <RepeatButton Grid.Row="2" Command="ScrollBar.LineDownCommand" Focusable="False" IsTabStop="False">
                <RepeatButton.Template>
                  <ControlTemplate TargetType="RepeatButton">
                    <Border x:Name="bd" Background="Transparent">
                      <Path x:Name="ad" Data="M 0 0 L 10 0 L 5 6 Z" Fill="#5A6A75" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="bd" Property="Background" Value="#13202B"/>
                        <Setter TargetName="ad" Property="Fill" Value="#36F9A6"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </RepeatButton.Template>
              </RepeatButton>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#090D12" BorderBrush="#13202B" BorderThickness="0,0,0,1" Padding="22,15">
      <StackPanel>
        <StackPanel Orientation="Horizontal">
          <Border Width="20" Height="20" Background="#00000000" BorderBrush="#36F9A6" BorderThickness="2" CornerRadius="3" Margin="0,0,10,0" VerticalAlignment="Center">
            <Border Width="8" Height="8" Background="#36F9A6" CornerRadius="1"/>
          </Border>
          <TextBlock Text="BOOST" Foreground="#EAF6F0" FontSize="22" FontWeight="Bold"/>
          <TextBlock Text="_" Foreground="#36F9A6" FontSize="22" FontWeight="Bold"/>
          <TextBlock x:Name="OsTag" Text="" Foreground="#8A99A4" FontSize="12" VerticalAlignment="Bottom" Margin="14,0,0,4"/>
        </StackPanel>
        <TextBlock Text="soft projetos // otimizador de windows 10 e 11" Foreground="#52606C" FontSize="11" Margin="0,4,0,0"/>
      </StackPanel>
    </Border>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="210"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="#090D12" BorderBrush="#13202B" BorderThickness="0,0,1,0">
        <StackPanel x:Name="SideNav" Margin="0,12,0,0"/>
      </Border>

      <Grid Grid.Column="1" Margin="22,16,22,16">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock x:Name="ModeTitle" Text="" Foreground="#36F9A6" FontSize="16" FontWeight="Bold"/>
            <TextBlock x:Name="ModeDesc" Text="" Foreground="#52606C" FontSize="11" Margin="0,3,0,0"/>
          </StackPanel>
          <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
            <Button x:Name="BtnRec" Content="recomendados" Style="{StaticResource Ghost}"/>
            <Button x:Name="BtnAll" Content="tudo" Style="{StaticResource Ghost}"/>
            <Button x:Name="BtnNone" Content="padrão" Style="{StaticResource Ghost}"/>
          </StackPanel>
        </Grid>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="ContentHost"/></ScrollViewer>

        <CheckBox Grid.Row="2" x:Name="ChkRestore" Content="criar ponto de restauração antes de aplicar" IsChecked="False" Margin="2,14,0,12"/>

        <Grid Grid.Row="3">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border Grid.Column="0" Background="#04070A" BorderBrush="#14202B" BorderThickness="1" CornerRadius="5" Margin="0,0,14,0">
            <TextBox x:Name="StatusBox" Height="124" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="#00000000" Foreground="#36F9A6" BorderThickness="0" FontFamily="Consolas" FontSize="11" Padding="11"/>
          </Border>
          <StackPanel Grid.Column="1" VerticalAlignment="Bottom" Width="156">
            <Button x:Name="BtnClose" Content="SAIR" Style="{StaticResource Ghost}"/>
          </StackPanel>
        </Grid>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@

# ---- Modos (menu lateral) ----
$modes = @(
  @{ Key='limpeza'; Kind='action';     Label='LIMPEZA';        Cat='Limpeza';                    Desc='remove arquivos temporários e caches' }
  @{ Key='gamer'; Kind='toggle';       Label='GAMER';          Cat='Desempenho & Jogos';         Desc='energia máxima, HAGS, game mode e sem game dvr' }
  @{ Key='privacidade'; Kind='toggle'; Label='PRIVACIDADE';    Cat='Privacidade & Telemetria';   Desc='telemetria, anúncios e sugestões desligados' }
  @{ Key='apps'; Kind='toggle';        Label='APPS WINDOWS';           Cat='Apps / Tranqueiras';         Desc='remove apps pré-instalados que você não usa' }
  @{ Key='programas'; Kind='install';  Label='APPS';      Cat='__install__';                Desc='instale programas uteis (via winget)' }
  @{ Key='updates'; Kind='update';     Label='WINDOWS UPDATE'; Cat='__updates__';                Desc='controle as atualizações do Windows' }
)

function Write-Status {
    param([string]$Msg)
    $line = ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Msg)
    Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
    if ($script:StatusBox) {
        $script:StatusBox.AppendText($line + "`r`n")
        $script:StatusBox.ScrollToEnd()
        $script:Window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }
}

function Show-Mode {
    param([string]$Key)
    $script:CurrentMode = $Key
    if (-not $script:Panels[$Key].Built) {
        Build-ModeContent $script:Panels[$Key].Mode $script:Panels[$Key].Panel
        $script:Panels[$Key].Built = $true
        if ($Key -eq 'updates') { Update-WUHighlight }
    }
    foreach ($k in @($script:Panels.Keys)) {
        $script:Panels[$k].Panel.Visibility = $(if ($k -eq $Key) { 'Visible' } else { 'Collapsed' })
        $nb = $script:NavButtons[$k]
        if ($k -eq $Key) { $nb.Background=(Brush '#101A24'); $nb.Foreground=(Brush '#36F9A6'); $nb.FontWeight='Bold' }
        else { $nb.Background=(Brush '#00000000'); $nb.Foreground=(Brush '#7E8C99'); $nb.FontWeight='Normal' }
    }
    $m = $script:Panels[$Key].Mode
    $script:ModeTitle.Text = '[ ' + $m.Label + ' ]'
    $script:ModeDesc.Text  = $m.Desc
    $vis = $(if ($script:Panels[$Key].Mode.Kind -eq 'toggle') { 'Visible' } else { 'Collapsed' })
    foreach ($bn in 'BtnRec','BtnAll','BtnNone') { $b=$script:Window.FindName($bn); if ($b) { $b.Visibility = $vis } }
}

function Bulk-Toggle {
    param([string]$How)
    $cat = $script:Panels[$script:CurrentMode].Mode.Cat
    foreach ($t in ($script:Tweaks | Where-Object { $_.Cat -eq $cat })) {
        if (-not $t.Sw) { continue }
        if ($How -eq 'rec' -and -not $t.Default) { continue }
        $optOn = if ($t.Invert) { $false } else { $true }
        $desired = if ($How -eq 'none') { -not $optOn } else { $optOn }
        if ([bool]$t.Sw.IsChecked -eq $desired) { continue }
        try {
            Run-Action $t $desired
            $t.Sw.IsChecked = $desired
            $w = if ($t.Invert) { if ($desired) { 'instalado: ' } else { 'removido: ' } } else { if ($desired) { 'ligado:  ' } else { 'desligado: ' } }
            Write-Status ($w + $t.Name)
        } catch { Write-Status ('erro: ' + $t.Name + ' - ' + $_.Exception.Message) }
    }
    Write-Status 'pronto.'
}

function Ensure-RestorePoint {
    if ($script:RestoreDone -or -not $script:ChkRestore.IsChecked) { return }
    Write-Status 'criando ponto de restauração...'
    if (New-BoostRestorePoint) { Write-Status 'ponto de restauração criado.' }
    else { Write-Status 'AVISO: sem ponto de restauração (proteção do sistema pode estar off). seguindo...' }
    $script:RestoreDone = $true
}
function Run-Action {
    param($t, [bool]$On)
    $doApply = if ($t.Invert) { -not $On } else { $On }
    if ($doApply) { Ensure-RestorePoint; & $t.Apply $t } else { & $t.Revert $t }
}

function Slide-Knob($tb) {
    if (-not $tb) { return }
    $tt = $tb.Template.FindName('kx', $tb)
    if (-not $tt) { return }
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.To = $(if ($tb.IsChecked) { 26.0 } else { 0.0 })
    $anim.Duration = New-Object System.Windows.Duration -ArgumentList ([TimeSpan]::FromMilliseconds(160))
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseOut'
    $anim.EasingFunction = $ease
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $anim)
}

function Test-Winget { return [bool](Get-WingetPath) }

function Start-AppInstall($btn, $name, $wid) {
    if (-not (Test-Winget)) { Write-Status 'winget nao encontrado. instale o App Installer pela Microsoft Store.'; return }
    $btn.IsHitTestVisible = $false
    $btn.Content = 'na fila...'
    $script:InstallQueue += @{ Btn = $btn; Name = $name; Wid = $wid }
    Pump-Installs
}

function Pump-Installs {
    if ($script:InstallActive) { return }
    if (-not $script:InstallQueue -or $script:InstallQueue.Count -eq 0) {
        if ($script:InstallTimer) { $script:InstallTimer.Stop(); $script:InstallTimer = $null }
        return
    }
    $job = $script:InstallQueue[0]
    $script:InstallQueue = @($script:InstallQueue | Select-Object -Skip 1)
    $job.Btn.Content = 'instalando...'
    Write-Status ('instalando: ' + $job.Name + ' ...')
    $wg = Get-WingetPath
    if (-not $wg) {
        $job.Btn.Content = 'instalar'; $job.Btn.IsHitTestVisible = $true
        Write-Status 'winget nao encontrado.'
        Pump-Installs; return
    }
    try {
        $proc = Start-Process -FilePath $wg -ArgumentList @('install','--id',$job.Wid,'--silent','--accept-package-agreements','--accept-source-agreements','--force','--disable-interactivity','--source','winget') -WindowStyle Hidden -PassThru -ErrorAction Stop
        $script:InstallActive = @{ Proc = $proc; Btn = $job.Btn; Name = $job.Name }
        Ensure-InstallTimer
    } catch {
        $job.Btn.Content = 'instalar'; $job.Btn.IsHitTestVisible = $true
        Write-Status ('erro instalando ' + $job.Name + ': ' + $_.Exception.Message)
        Pump-Installs
    }
}

function Ensure-InstallTimer {
    if ($script:InstallTimer) { return }
    $script:InstallTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:InstallTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:InstallTimer.Add_Tick({
        $job = $script:InstallActive
        if (-not $job) { Pump-Installs; return }
        try { if (-not $job.Proc.HasExited) { return } } catch { }
        $ec = -1
        try { $ec = $job.Proc.ExitCode } catch { }
        if ($ec -eq 0) { Set-AppInstalled $job.Btn; Write-Status ('ok: ' + $job.Name + ' instalado.') }
        else {
            $job.Btn.Content = 'instalar'; $job.Btn.IsHitTestVisible = $true
            Write-Status ($job.Name + ': winget saiu com codigo ' + $ec + ' (pode ja estar instalado ou cancelado).')
        }
        $script:InstallActive = $null
        Pump-Installs
    })
    $script:InstallTimer.Start()
}

function Set-AppInstalled($btn) {
    if (-not $btn) { return }
    $btn.Content = 'instalado'
    $btn.Foreground = (Brush '#36F9A6')
    $btn.IsHitTestVisible = $false
}

function Get-WingetPath {
    $real = Get-ChildItem (Join-Path $env:ProgramFiles 'WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe') -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($real) { return $real.FullName }
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $alias) { return $alias }
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}
function Start-AppDetection {
    if ($script:DetectStarted) { return }
    $script:DetectStarted = $true
    $wg = Get-WingetPath
    if (-not $wg) { Write-Status 'winget nao encontrado: nao da pra detectar instalados.'; return }
    Write-Status 'verificando programas ja instalados (winget)...'
    $script:DetectFile = Join-Path $env:TEMP ('boost-wg-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $script:DetectProc = Start-Process -FilePath $wg -ArgumentList @('export','-o',$script:DetectFile,'--accept-source-agreements','--nowarn','--disable-interactivity') -WindowStyle Hidden -PassThru -ErrorAction Stop
    } catch {
        Write-Status ('erro ao iniciar winget: ' + $_.Exception.Message); return
    }
    $script:DetectTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:DetectTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:DetectTimer.Add_Tick({
        try { if (-not $script:DetectProc.HasExited) { return } } catch { }
        $script:DetectTimer.Stop()
        $ids = @{}
        try {
            if (Test-Path $script:DetectFile) {
                $j = Get-Content $script:DetectFile -Raw -ErrorAction Stop | ConvertFrom-Json
                foreach ($src in $j.Sources) { foreach ($pk in $src.Packages) { if ($pk.PackageIdentifier) { $ids[$pk.PackageIdentifier.ToLower()] = $true } } }
                Remove-Item $script:DetectFile -Force -ErrorAction SilentlyContinue
            }
        } catch { Write-Status ('erro ao ler winget export: ' + $_.Exception.Message) }
        $count = 0
        foreach ($b in $script:InstallBtns) {
            $app = $b.Tag
            if ($app -and $ids.ContainsKey(([string]$app.W).ToLower())) { Set-AppInstalled $b; $count++ }
        }
        Write-Status ('verificacao concluida: ' + $count + ' ja instalados (de ' + $ids.Count + ' detectados).')
    })
    $script:DetectTimer.Start()
}
# ---- Windows Update (3 estados) ----
function Set-WUState {
    param([string]$State)
    $pol='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $au ='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $ux ='HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    if ($State -eq 'on') {
        Remove-Item $pol -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($v in 'DeferFeatureUpdates','DeferFeatureUpdatesPeriodInDays','DeferQualityUpdates','DeferQualityUpdatesPeriodInDays') { Remove-Reg $ux $v }
        foreach ($s in 'wuauserv','UsoSvc','WaaSMedicSvc') {
            Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\$s" 'Start' $(if ($s -eq 'UsoSvc') {2} else {3})
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
        }
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like '\Microsoft\Windows\WindowsUpdate\*' -or $_.TaskPath -like '\Microsoft\Windows\UpdateOrchestrator\*' } | Enable-ScheduledTask -ErrorAction SilentlyContinue
    }
    elseif ($State -eq 'security') {
        foreach ($s in 'wuauserv','UsoSvc') {
            Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\$s" 'Start' $(if ($s -eq 'UsoSvc') {2} else {3})
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
        }
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Remove-Reg $au 'NoAutoUpdate'
        foreach ($base in @($ux,$pol)) {
            Set-Reg $base 'DeferFeatureUpdates' 1
            Set-Reg $base 'DeferFeatureUpdatesPeriodInDays' 365
            Set-Reg $base 'DeferQualityUpdates' 0
            Set-Reg $base 'DeferQualityUpdatesPeriodInDays' 0
        }
    }
    else {
        Set-Reg $au 'NoAutoUpdate' 1
        Set-Reg $au 'AUOptions' 1
        foreach ($s in 'wuauserv','UsoSvc','WaaSMedicSvc') {
            Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\$s" 'Start' 4
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        }
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like '\Microsoft\Windows\WindowsUpdate\*' -or $_.TaskPath -like '\Microsoft\Windows\UpdateOrchestrator\*' } | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }
}

function Get-WUState {
    $st = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv' -Name Start -ErrorAction SilentlyContinue).Start
    if ($st -eq 4 -or (Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1)) { return 'off' }
    $a = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -Name DeferFeatureUpdatesPeriodInDays -ErrorAction SilentlyContinue).DeferFeatureUpdatesPeriodInDays
    $b = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name DeferFeatureUpdatesPeriodInDays -ErrorAction SilentlyContinue).DeferFeatureUpdatesPeriodInDays
    if (($a -ge 1) -or ($b -ge 1)) { return 'security' }
    return 'on'
}

function Update-WUHighlight {
    $cur = Get-WUState
    foreach ($id in @($script:UpdCards.Keys)) {
        $c = $script:UpdCards[$id]
        if ($id -eq $cur) { $c.BorderBrush=(Brush '#36F9A6'); $c.Background=(Brush '#0E1A16') }
        else { $c.BorderBrush=(Brush '#22303C'); $c.Background=(Brush '#0A1118') }
    }
}

function Invoke-WUOption {
    param([string]$Id)
    if ($script:ChkRestore.IsChecked) {
        Write-Status 'criando ponto de restauração...'
        if (New-BoostRestorePoint) { Write-Status 'ponto de restauração criado.' } else { Write-Status 'AVISO: sem ponto de restauração. seguindo...' }
    }
    try {
        Set-WUState $Id
        $label = switch ($Id) { 'on' { 'ativado' } 'security' { 'apenas segurança' } 'off' { 'desativado' } }
        Write-Status ('Windows Update -> ' + $label)
    } catch { Write-Status ('-- update: ' + $_.Exception.Message) }
    Update-WUHighlight
}

# ---- Opções de Windows Update ----
$updOptions = @(
  @{ Id='on';       Title='Ativado (padrão do Windows)';      Avs=$false; Desc='Recebe todas as atualizações normalmente. Recomendado.' }
  @{ Id='security'; Title='Apenas atualizações de segurança'; Avs=$false; Desc='Adia os upgrades de versão (ex.: 23H2 para 24H2) por até 1 ano, mas continua recebendo correções de segurança e qualidade. Em algumas edições Home o Windows pode não respeitar 100%.' }
  @{ Id='off';      Title='Totalmente desativado';            Avs=$true;  Desc='Desliga o serviço e as tarefas de update. NÃO recomendado a longo prazo: você fica sem patches de segurança. Um feature update grande do Windows pode reativar.' }
)

function Ensure-Installed {
    if ($script:InstalledReady) { return }
    foreach ($p in (Get-AppxPackage -ErrorAction SilentlyContinue)) { $script:Installed[$p.Name] = $true }
    $script:InstalledReady = $true
}

function Build-ModeContent {
    param($m, $panel)
    if ($m.Key -eq 'apps') { Ensure-Installed }
        if ($m.Kind -eq 'update') {
            $intro = New-Object System.Windows.Controls.TextBlock
            $intro.Text = 'clique no modo desejado (aplica na hora). o modo ativo fica destacado em verde.'
            $intro.Foreground = (Brush '#52606C'); $intro.FontSize = 11; $intro.Margin = (Thk 2 0 0 12); $intro.TextWrapping = 'Wrap'
            $panel.AddChild($intro)
            foreach ($opt in $updOptions) {
                $card = New-Object System.Windows.Controls.Border
                $card.Background = (Brush '#0A1118'); $card.BorderBrush = (Brush '#22303C')
                $card.BorderThickness = (Thk 1 1 1 1); $card.CornerRadius = (New-Object System.Windows.CornerRadius(6))
                $card.Padding = (Thk 15 13 15 13); $card.Margin = (Thk 0 0 0 10)
                $card.Cursor = [System.Windows.Input.Cursors]::Hand
                $card.Tag = $opt.Id
                $cspg = New-Object System.Windows.Controls.StackPanel
                $ct = New-Object System.Windows.Controls.TextBlock
                $ct.Text = $opt.Title; $ct.FontSize = 14; $ct.FontWeight = 'Bold'
                $ct.Foreground = (Brush $(if ($opt.Avs) { '#FF7088' } else { '#D6E5DE' }))
                $cspg.AddChild($ct)
                $cd = New-Object System.Windows.Controls.TextBlock
                $cd.Text = $opt.Desc; $cd.TextWrapping = 'Wrap'; $cd.FontSize = 11; $cd.Foreground = (Brush '#52606C'); $cd.Margin = (Thk 0 4 0 0)
                $cspg.AddChild($cd)
                $card.Child = $cspg
                $card.Add_MouseLeftButtonUp({ param($snd,$e) Invoke-WUOption $snd.Tag })
                $panel.AddChild($card)
                $script:UpdCards[$opt.Id] = $card
            }
        }
        elseif ($m.Kind -eq 'action') {
            $intro = New-Object System.Windows.Controls.TextBlock
            $intro.Text = 'clique pra executar a limpeza na hora.'
            $intro.Foreground = (Brush '#52606C'); $intro.FontSize = 11; $intro.Margin = (Thk 2 0 0 12); $intro.TextWrapping = 'Wrap'
            $panel.AddChild($intro)
            foreach ($t in ($script:Tweaks | Where-Object { $_.Cat -eq $m.Cat })) {
                $card = New-Object System.Windows.Controls.Border
                $card.Background = (Brush '#0A1118'); $card.BorderBrush = (Brush '#22303C')
                $card.BorderThickness = (Thk 1 1 1 1); $card.CornerRadius = (New-Object System.Windows.CornerRadius(6))
                $card.Padding = (Thk 15 13 15 13); $card.Margin = (Thk 0 0 0 10)
                $card.Cursor = [System.Windows.Input.Cursors]::Hand
                $card.Tag = $t
                $sp = New-Object System.Windows.Controls.StackPanel
                $ct = New-Object System.Windows.Controls.TextBlock
                $ct.Text = $t.Name; $ct.FontSize = 14; $ct.FontWeight = 'Bold'; $ct.Foreground = (Brush '#D6E5DE')
                $sp.AddChild($ct)
                $cd = New-Object System.Windows.Controls.TextBlock
                $cd.Text = $t.Desc; $cd.TextWrapping = 'Wrap'; $cd.FontSize = 11; $cd.Foreground = (Brush '#52606C'); $cd.Margin = (Thk 0 4 0 0)
                $sp.AddChild($cd)
                $card.Child = $sp
                $card.Add_MouseLeftButtonUp({ param($snd,$e)
                    $tw = $snd.Tag
                    try { & $tw.Apply $tw; Write-Status ('feito: ' + $tw.Name) }
                    catch { Write-Status ('erro: ' + $tw.Name + ' - ' + $_.Exception.Message) }
                })
                $panel.AddChild($card)
            }
        }
        elseif ($m.Kind -eq 'install') {
            $intro = New-Object System.Windows.Controls.TextBlock
            $intro.Text = 'clique em instalar (usa o winget, precisa de internet). instala a versao mais recente do programa.'
            $intro.Foreground = (Brush '#52606C'); $intro.FontSize = 11; $intro.Margin = (Thk 2 0 0 12); $intro.TextWrapping = 'Wrap'
            $panel.AddChild($intro)
            $script:InstallBtns = @()
            $grpNames = $externalApps | ForEach-Object { $_.G } | Select-Object -Unique | Sort-Object
            foreach ($gname in $grpNames) {
                $gh = New-Object System.Windows.Controls.TextBlock
                $gh.Text = $gname; $gh.FontSize = 12; $gh.FontWeight = 'Bold'; $gh.Foreground = (Brush '#36F9A6'); $gh.Margin = (Thk 0 14 0 6)
                $panel.AddChild($gh)
                foreach ($app in ($externalApps | Where-Object { $_.G -eq $gname } | Sort-Object { $_.N })) {
                    $row = New-Object System.Windows.Controls.StackPanel
                    $row.Orientation = 'Horizontal'; $row.Margin = (Thk 2 3 0 3)
                    $ib = New-Object System.Windows.Controls.Button
                    if ($script:ghostStyle) { $ib.Style = $script:ghostStyle }
                    $ib.Content = 'instalar'; $ib.Tag = $app; $ib.MinWidth = 78
                    $ib.Add_Click({ param($snd,$e)
                        $a = $snd.Tag
                        Start-AppInstall $snd $a.N $a.W
                    })
                    $row.AddChild($ib)
                    $script:InstallBtns += $ib
                    $nm = New-Object System.Windows.Controls.TextBlock
                    $nm.Text = $app.N; $nm.VerticalAlignment = 'Center'; $nm.FontSize = 12; $nm.Foreground = (Brush '#CBD8E2'); $nm.Margin = (Thk 12 0 0 0)
                    $row.AddChild($nm)
                    $panel.AddChild($row)
                }
            }
            Start-AppDetection
        }
        else {
            $hint = New-Object System.Windows.Controls.TextBlock
            $hint.Text = $(if ($m.Key -eq 'apps') { 'verde = instalado (voce tem), vermelho = removido. desligue o que nao usa.' } else { 'verde = otimizacao ligada, vermelho = padrao do Windows.' })
            $hint.Foreground = (Brush '#52606C'); $hint.FontSize = 11; $hint.Margin = (Thk 2 0 0 12); $hint.TextWrapping = 'Wrap'
            $panel.AddChild($hint)
            foreach ($t in ($script:Tweaks | Where-Object { $_.Cat -eq $m.Cat })) {
                $row = New-Object System.Windows.Controls.StackPanel
                $row.Margin = (Thk 2 10 0 4)
                $top = New-Object System.Windows.Controls.StackPanel
                $top.Orientation = 'Horizontal'
                $sw = New-Object System.Windows.Controls.Primitives.ToggleButton
                if ($script:swStyle) { $sw.Style = $script:swStyle }
                $sw.VerticalAlignment = 'Center'
                $state = $false; try { $state = [bool](& $t.Test $t) } catch { $state = $false }
                $sw.IsChecked = $(if ($t.Invert) { -not $state } else { $state })
                $sw.Tag = $t
                $sw.Add_Loaded({ param($snd,$e) $tt = $snd.Template.FindName('kx', $snd); if ($tt) { $tt.X = $(if ($snd.IsChecked) { 26 } else { 0 }) } })
                $sw.Add_Click({ param($snd,$e)
                    $tw = $snd.Tag; $on = [bool]$snd.IsChecked
                    Slide-Knob $snd
                    try {
                        Run-Action $tw $on
                        $w = if ($tw.Invert) { if ($on) { 'instalado: ' } else { 'removido: ' } } else { if ($on) { 'ligado:  ' } else { 'desligado: ' } }
                        Write-Status ($w + $tw.Name)
                        if ($tw.Reboot -and $on) { Write-Status '   -> requer REINICIAR pra valer' }
                    } catch { $snd.IsChecked = -not $on; Slide-Knob $snd; Write-Status ('erro: ' + $tw.Name + ' - ' + $_.Exception.Message) }
                })
                $top.AddChild($sw)
                $nm = New-Object System.Windows.Controls.TextBlock
                $nm.Text = $t.Name; $nm.FontSize = 13; $nm.VerticalAlignment = 'Center'; $nm.Margin = (Thk 12 0 0 0)
                $nm.Foreground = (Brush $(if ($t.Warn) { '#FF7088' } else { '#CBD8E2' }))
                $top.AddChild($nm)
                $row.AddChild($top)
                $d = New-Object System.Windows.Controls.TextBlock
                $d.Text = $t.Desc; $d.TextWrapping = 'Wrap'; $d.FontSize = 11
                $d.Foreground = (Brush $(if ($t.Warn) { '#FF7088' } else { '#52606C' }))
                $d.Margin = (Thk 58 3 12 0)
                $row.AddChild($d)
                $t | Add-Member -NotePropertyName Sw -NotePropertyValue $sw -Force
                $panel.AddChild($row)
            }
        }
}

try {
    $script:Window    = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    $SideNav          = $script:Window.FindName('SideNav')
    $ContentHost      = $script:Window.FindName('ContentHost')
    $script:StatusBox = $script:Window.FindName('StatusBox')
    $script:ChkRestore= $script:Window.FindName('ChkRestore')
    $script:ModeTitle = $script:Window.FindName('ModeTitle')
    $script:ModeDesc  = $script:Window.FindName('ModeDesc')

    # rede de seguranca: qualquer excecao nao tratada em handler/timer eh logada, NAO derruba o app
    $script:Window.Dispatcher.add_UnhandledException({ param($snd,$e)
        $e.Handled = $true
        try { Write-Status ('!! erro capturado (app continua): ' + $e.Exception.Message) } catch {}
    })

    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $pn = $cv.ProductName
        if ($pn) {
            $pn = ($pn -replace 'Microsoft ', '').Trim()
            $build = 0; try { $build = [int]$cv.CurrentBuild } catch {}
            if ($build -ge 22000) { $pn = $pn -replace 'Windows 10', 'Windows 11' }
            $script:Window.FindName('OsTag').Text = '// ' + $pn + '  ·  ' + $env:COMPUTERNAME
        }
    } catch {}

    $navStyle = $script:Window.Resources['Nav']
    $script:swStyle = $script:Window.Resources['Switch']
    $script:ghostStyle = $script:Window.Resources['Ghost']
    $script:RestoreDone = $false
    $script:InstallQueue = @()
    $script:InstallActive = $null
    $script:InstallTimer = $null
    $script:Panels = @{}
    $script:NavButtons = @{}
    $script:UpdCards = @{}

    foreach ($m in $modes) {
        $nb = New-Object System.Windows.Controls.Button
        if ($navStyle) { $nb.Style = $navStyle }
        $nb.Content = '> ' + $m.Label
        $nb.Tag = $m.Key
        $nb.Add_Click({ param($snd,$e) try { Show-Mode $snd.Tag } catch { Write-Status ('erro abrindo ' + $snd.Tag + ': ' + $_.Exception.Message) } })
        $SideNav.AddChild($nb)
        $script:NavButtons[$m.Key] = $nb

        $panel = New-Object System.Windows.Controls.StackPanel
        $panel.Visibility = 'Collapsed'
        $ContentHost.AddChild($panel)
        $script:Panels[$m.Key] = @{ Panel = $panel; Mode = $m; Built = $false }
    }

    $script:Window.FindName('BtnRec').Add_Click({ Bulk-Toggle 'rec' })
    $script:Window.FindName('BtnAll').Add_Click({ Bulk-Toggle 'all' })
    $script:Window.FindName('BtnNone').Add_Click({ Bulk-Toggle 'none' })
    $script:Window.FindName('BtnClose').Add_Click({ $script:Window.Close() })

    Update-WUHighlight
    Show-Mode 'gamer'
    Write-Status 'pronto. cada item tem um botao ON/OFF: verde = ligado, vermelho = desligado. clica e aplica/reverte na hora.'
    Write-Status ('log: ' + $script:LogFile)
    $script:Window.ShowDialog() | Out-Null
}
catch {
    [System.Windows.MessageBox]::Show($_.Exception.Message, 'Boost - erro') | Out-Null
}
