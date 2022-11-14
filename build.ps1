param(
  # Use docker compose
  [Parameter(Position = 0, Mandatory = $False, HelpMessage = "Enables the use of Docker Compose")]
  [Switch]
  $Compose,
  # Disable Build
  [Parameter(Position = 1, Mandatory = $False, HelpMessage = "Disable Build")]
  [Switch]
  $NoBuild
)

$Docker = (Get-Command "docker.exe");
if (-not (Test-Path -Path $Docker.Source -PathType Leaf)) {
  Write-Error -Message "Docker executable not found.";
  Exit 1;
}

function ReadCompseFile() {
  try {
    Import-Module FXPSYaml -ErrorAction Stop
  }
  catch {
    Write-Error -Message "Module PSYaml is not installed."
    Exit 1;
  }

  if (-not (Test-Path -Path "$($PSScriptRoot)\.docker\docker-compose.yml")) {
    Write-Error -Message "Docker Compose file not found";
    return $null;
  }
  $YamlObject = (ConvertFrom-Yaml -Path "$($PSScriptRoot)\.docker\docker-compose.yml" -ErrorAction Stop);
  return $YamlObject;
  Remove-Module FXPSYaml -ErrorAction Stop
}

function AskForInput() {
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

function CheckPassword() {
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
    $FlamePassword = (AskForInput -Question "Flame Password?" -Default (((Test-Path "$($PSScriptRoot)\secrets\flame_password") && (Get-Content "$($PSScriptRoot)\secrets\flame_password")) || "password"));
    return $FlamePassword;
  }
}

function ComposeBuild() {
  $ComposeFile = (ReadCompseFile);
  $DockerContainer = $ComposeFile.services.flame.container_name;
  if (-not $NoBuild) {
    &$Docker rmi $ComposeFile.services.flame.image
    &$Docker build --no-cache --progress=plain -t $ComposeFile.services.flame.image -f .\.docker\Dockerfile .
    # &$Docker compose build --no-cache --progress=plain
  }
  if (-not (Test-Path -Path "$($env:AppData)\run")) {
    New-Item -Path "$($env:AppData)\run" -ItemType Directory;
  }
  if (Test-Path -Path "$($env:AppData)\run\flame.cid") {
    Remove-Item "$($env:AppData)\run\flame.cid";
  }
  &$Docker compose up --detach
  &$Docker update --restart unless-stopped $DockerContainer
  (((docker container ls --no-trunc) | Select-String ($ComposeFile.services.flame.image -replace ":.*$", "")) -split " ")[0] | Out-File "$($env:AppData)\run\flame.cid"
}

function NormalBuild() {
  $DockerContainer = (AskForInput -Question "Docker Container Name?" -Default "Flame");
  &$Docker container stop $DockerContainer
  &$Docker rm $DockerContainer
  $DockerImage = (AskForInput -Question "Docker Image Name?" -Default "Flame");
  if (-not $NoBuild) {
    &$Docker rmi $DockerImage
    &$Docker build --no-cache --progress=plain -t $DockerImage -f .\.docker\Dockerfile .
  }
  Remove-Item "$($env:AppData)\run\flame.cid"
  $FlamePassword = (AskForInput -Question "Flame Password?" -Default (((Test-Path "$($PSScriptRoot)\secrets\flame_password") && (Get-Content "$($PSScriptRoot)\secrets\flame_password")) || "password"));
  &$Docker create --name $DockerContainer --cidfile "$($env:AppData)\run\flame.cid" --mount type=volume, src=Flame, target=/app/data -p 80:5005 -e PASSWORD $FlamePassword ($DockerImage -replace ":.*$", "")
  &$Docker container start $DockerContainer
  &$Docker update --restart unless-stopped $DockerContainer
}

if ($Compose) {
  ComposeBuild;
}
else {
  NormalBuild;
}