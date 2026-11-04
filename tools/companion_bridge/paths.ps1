function Get-CompanionDataRoot {
    if ($env:MY_FRIEND_ASSISTANT_DATA_DIR) {
        return [IO.Path]::GetFullPath($env:MY_FRIEND_ASSISTANT_DATA_DIR)
    }
    return Join-Path $PSScriptRoot '.local'
}
