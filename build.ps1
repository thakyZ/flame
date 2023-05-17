[CmdletBinding(DefaultParameterSetName = "Docker")]
param(
  # Use docker compose
  [Parameter(Position = 0, Mandatory = $False, HelpMessage = "Enables the use of Docker Compose", ParameterSetName = "Docker")]
  [Switch]
  $Compose,
  # Disable Build
  [Parameter(Position = 1, Mandatory = $False, HelpMessage = "Disable Build", ParameterSetName = "Docker")]
  [Switch]
  $NoBuild,
  # Disable Docker, build locally.
  [Parameter(Position = 0, Mandatory = $False, HelpMessage = "Disable Docker, build locally.", ParameterSetName = "Local")]
  [Switch]
  $NoBuild,
)

function Read-Input() {
  param(
    # The question to be asked
    [Parameter(Position = 0, Mandatory = $True, HelpMessage = "The question to be asked")]
    [String]
    $Question,
    # Default Parameter
    [Parameter(Position = 1, Mandatory = $True, HelpMessage = "The default answer.")]
    [String]
    $Default
  )
  $Answer = Read-Host -Prompt "$($Question) [$($Default)]"
  if ([string]::IsNullOrWhiteSpace($Answer)) {
    $Answer = $Default
  }
  return $Answer;
}

function Test-Password() {
  param (
    # Compose File Object
    [Parameter(Position = 0, Mandatory = $True, HelpMessage = "Compose File Object")]
    [psobject]
    $Object
  )

  if (($null -ne $Object.services.flame.secrets) -and ([string]::IsNullOrWhiteSpace($Object.services.flame.secrets[0]))) {
    return $Object.services.flame.secrets[0]
  }
  elseif (($null -ne $Object.services.flame.environment) -and ($Object.services.flame.environment[0] -match "PASSWORD=")) {
    return ($Object.services.flame.environment[0] -replace "PASSWORD=", "");
  }
  elseif (($null -ne $Object.services.flame.environment) -and ($Object.services.flame.environment[0] -match "PASSWORD_FILE=")) {
    return (Get-Content -Path ($Object.services.flame.environment[0] -replace "PASSWORD_FILE=", ""));
  }
  elseif (($null -ne $Object.secrets.password.file) -and ([string]::IsNullOrWhiteSpace($Object.secrets.password.file))) {
    return (Get-Content -Path $Object.secrets.password.file);
  }
  else {
    $FlamePassword = (Read-Input -Question "Flame Password?" -Default (((Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "secrets" -AdditionalChildPath "flame_password")) && (Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "secrets" -AdditionalChildPath "flame_password"))) || "password"));
    return $FlamePassword;
  }
}

Function Invoke-BuildViaDocker() {
  $Docker = (Get-Command -Name "docker");
  if (-not (Test-Path -LiteralPath $Docker.Source -PathType Leaf)) {
    Write-Error -Message "Docker executable not found.";
    Exit 1;
  }

  function Read-CompseFile() {
    try {
      Import-Module -Name "powershell-yaml" -ErrorAction Stop
    }
    catch {
      Write-Error -Message "Module PSYaml is not installed."
      Exit 1;
    }

    if (-not (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath ".docker" -AdditionalChildPath "docker-compose.yml"))) {
      Write-Error -Message "Docker Compose file not found";
      return $null;
    }
    $YamlObject = (Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath ".docker" -AdditionalChildPath "docker-compose.yml") -ErrorAction Stop | ConvertFrom-Yaml);
    return $YamlObject;
    Remove-Module -Name "powershell-yaml" -ErrorAction Stop
  }

  Function Get-DockerFile() {
    param(
      # File Name
      [Parameter(Mandatory = $True)]
      [string]
      $Value
    )

    $DockerFolder = (Join-Path -Path $PSScriptRoot -ChildPath ".docker");
    If (Test-Path -LiteralPath (Join-Path -Path $DockerFolder -ChildPath $Value) -PathType Leaf) {
      $Path = (Join-Path -Path $DockerFolder -ChildPath $Value);
      $Relavtive = (Resolve-Path -LiteralPath $Path -Relative);
      return $Relavtive;
    }
  }

  function Invoke-ComposeBuild() {
    $ComposeFile = (Read-CompseFile);
    $DockerContainer = $ComposeFile.services.flame.container_name;

    if (-not $NoBuild) {
      if ($null -ne (&$Docker images list | Select-String "$($ComposeFile.services.flame.image)")) {
        &$Docker rmi $ComposeFile.services.flame.image
      }
      &$Docker build --no-cache --progress=plain -t $ComposeFile.services.flame.image -f "$(Get-DockerFile -Value "Dockerfile")" .
      # &$Docker compose build --no-cache --progress=plain
    }
    if (-not (Test-Path -LiteralPath (Join-Path -Path $env:AppData -ChildPath "run"))) {
      New-Item -LiteralPath (Join-Path -Path $env:AppData -ChildPath "run") -ItemType Directory;
    }
    if (Test-Path -LiteralPath (Join-Path -Path $env:AppData -ChildPath "run" -AdditionalChildPath "flame.cid")) {
      Remove-Item -LiteralPath (Join-Path -Path $env:AppData -ChildPath "run" -AdditionalChildPath "flame.cid");
    }
    &$Docker compose up --detach "$(Get-DockerFile -Value "docker-compose.yml")"
    &$Docker update --restart unless-stopped $DockerContainer
    (((docker container ls --no-trunc) | Select-String ($ComposeFile.services.flame.image -replace ":.*$", "")) -split " ")[0] | Out-File (Join-Path -Path $env:AppData -ChildPath "run" -AdditionalChildPath "flame.cid")
  }

  function Invoke-NormalBuild() {
    $DockerContainer = (Read-Input -Question "Docker Container Name?" -Default "Flame");
    &$Docker container stop $DockerContainer
    &$Docker rm $DockerContainer
    $DockerImage = (Read-Input -Question "Docker Image Name?" -Default "Flame");
    if (-not $NoBuild) {
      &$Docker rmi $DockerImage
      &$Docker build --no-cache --progress=plain -t $DockerImage -f "$(Get-DockerFile -Value "Dockerfile")" .
    }
    Remove-Item -LiteralPath (Join-Path -Path $env:AppData -ChildPath "run" -AdditionalChildPath "flame.cid")
    $FlamePassword = (Read-Input -Question "Flame Password?" -Default (((Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "secrets" -AdditionalChildPath "flame_password")) && (Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath "secrets" -AdditionalChildPath "flame_password"))) || "password"));
    &$Docker create --name $DockerContainer --cidfile "$($env:AppData)\run\flame.cid" --mount type=volume, src=Flame, target=/app/data -p 80:5005 -e PASSWORD $FlamePassword ($DockerImage -replace ":.*$", "")
    &$Docker container start $DockerContainer
    &$Docker update --restart unless-stopped $DockerContainer
  }

  if ($Compose) {
    Invoke-ComposeBuild;
  }
  else {
    Invoke-NormalBuild;
  }
}

switch ($PsCmdlet.ParameterSetName) {
    "Docker" {
      Invoke-BuildViaDocker
    }
    "Local" {
      Invoke-BuildLocally
    }
    "__AllParameterSets" {
    }
}