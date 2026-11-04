param(
    [ValidateSet('check', 'recognize', 'hold', 'continuous', 'speak', 'selftest')][string]$Mode = 'check',
    [string]$Language = 'zh-CN',
    [ValidateRange(1, 20)][int]$Seconds = 8,
    [string]$WavePath = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
try {
    Add-Type -AssemblyName System.Speech
    $recognizers = @([System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers())
    if ($Mode -eq 'check') {
        $synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
        try {
            @{recognizers = @($recognizers | ForEach-Object { @{id = $_.Id; language = $_.Culture.Name; name = $_.Name} });
              voices = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object { @{name=$_.VoiceInfo.Name; language=$_.VoiceInfo.Culture.Name; gender=$_.VoiceInfo.Gender.ToString()} })} | ConvertTo-Json -Depth 4 -Compress
        } finally { $synth.Dispose() }
        exit 0
    }
    if ($Mode -eq 'speak') {
        $request = [Console]::In.ReadToEnd() | ConvertFrom-Json
        $synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
        try {
            $voice = @($synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq $Language })
            if (-not [string]::IsNullOrWhiteSpace([string]$request.voice)) { $synth.SelectVoice([string]$request.voice) }
            elseif ($voice.Count -gt 0) { $synth.SelectVoice($voice[0].VoiceInfo.Name) }
            if ($null -ne $request.rate) { $synth.Rate = [int]$request.rate }
            if ($null -ne $request.volume) { $synth.Volume = [int]$request.volume }
            $synth.Speak([string]$request.text)
            @{status = 'completed'} | ConvertTo-Json -Compress
        } finally { $synth.Dispose() }
        exit 0
    }
    $recognizerInfo = @($recognizers | Where-Object { $_.Culture.Name -eq $Language })
    if ($recognizerInfo.Count -eq 0) { throw "No installed recognizer for $Language. Install Windows speech language support." }
    $recognizer = [System.Speech.Recognition.SpeechRecognitionEngine]::new($recognizerInfo[0])
    try {
        $recognizer.LoadGrammar([System.Speech.Recognition.DictationGrammar]::new())
        if ($Mode -eq 'selftest') {
            if ([string]::IsNullOrWhiteSpace($WavePath)) { throw 'Supply a workspace-local WavePath for selftest.' }
            $synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
            try {
                $voice = @($synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq $Language })
                if ($voice.Count -gt 0) { $synth.SelectVoice($voice[0].VoiceInfo.Name) }
                $synth.SetOutputToWaveFile([System.IO.Path]::GetFullPath($WavePath))
                $synth.Speak('跑到暗影操控器旁边')
            } finally { $synth.Dispose() }
            $recognizer.SetInputToWaveFile([System.IO.Path]::GetFullPath($WavePath))
        } else { $recognizer.SetInputToDefaultAudioDevice() }
        if ($Mode -eq 'hold') {
            Add-Type -ReferencedAssemblies ([System.Speech.Recognition.SpeechRecognitionEngine].Assembly.Location) -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Speech.Recognition;
using System.Threading;
using System.Threading.Tasks;
public static class CompanionHeldRecognition {
    public static RecognitionResult[] Run(SpeechRecognitionEngine engine, int seconds) {
        var results = new List<RecognitionResult>();
        var completed = new ManualResetEventSlim(false);
        EventHandler<SpeechRecognizedEventArgs> recognized = (s,e) => { lock(results) results.Add(e.Result); };
        EventHandler<RecognizeCompletedEventArgs> done = (s,e) => completed.Set();
        engine.SpeechRecognized += recognized;
        engine.RecognizeCompleted += done;
        try {
            engine.RecognizeAsync(RecognizeMode.Multiple);
            Task.Run(() => Console.ReadLine()).Wait(TimeSpan.FromSeconds(seconds));
            engine.RecognizeAsyncStop();
            if (!completed.Wait(3000)) engine.RecognizeAsyncCancel();
            lock(results) return results.ToArray();
        } finally {
            engine.SpeechRecognized -= recognized;
            engine.RecognizeCompleted -= done;
        }
    }
}
'@
            $parts = @([CompanionHeldRecognition]::Run($recognizer, $Seconds))
            $text = ($parts | ForEach-Object { $_.Text }) -join ''
            @{text=$text; status=$(if ($text) {'recognized'} else {'no_speech'})} | ConvertTo-Json -Compress
            exit 0
        }
        if ($Mode -eq 'continuous') {
            while ($true) {
                $result = $recognizer.Recognize([TimeSpan]::FromSeconds($Seconds))
                if ($null -ne $result) {
                    $line = @{text = $result.Text; confidence = $result.Confidence; status = 'recognized'} | ConvertTo-Json -Compress
                    [Console]::WriteLine($line)
                    [Console]::Out.Flush()
                }
            }
        }
        $result = $recognizer.Recognize([TimeSpan]::FromSeconds($Seconds))
        if ($null -eq $result) { @{text = ''; confidence = 0; status = 'no_speech'} | ConvertTo-Json -Compress }
        else { @{text = $result.Text; confidence = $result.Confidence; status = 'recognized'} | ConvertTo-Json -Compress }
    } finally { $recognizer.Dispose() }
} catch {
    @{status = 'error'; error = $_.Exception.Message} | ConvertTo-Json -Compress
    exit 1
}
