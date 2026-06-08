package emdx

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadConfigMissingFileUsesDefaults(t *testing.T) {
	config, err := LoadConfigFromPath(filepath.Join(t.TempDir(), "missing.json"))
	if err != nil {
		t.Fatal(err)
	}

	if config.Port != 1515 {
		t.Fatalf("Port = %d, want 1515", config.Port)
	}
	if config.TimeoutSeconds != 120 {
		t.Fatalf("TimeoutSeconds = %d, want 120", config.TimeoutSeconds)
	}
	if !config.WaitForDownload {
		t.Fatal("WaitForDownload = false, want true")
	}
	if config.ImageFit != ImageFitOriginal {
		t.Fatalf("ImageFit = %q, want %q", config.ImageFit, ImageFitOriginal)
	}
	if config.CanvasWidth != 2560 || config.CanvasHeight != 1440 {
		t.Fatalf("canvas = %dx%d, want 2560x1440", config.CanvasWidth, config.CanvasHeight)
	}
	if config.CropX != 0.5 || config.CropY != 0.5 {
		t.Fatalf("crop = %.1f,%.1f, want 0.5,0.5", config.CropX, config.CropY)
	}
}

func TestSaveAndLoadConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".mdc", "config.json")
	want := Config{
		Host:            "192.168.1.225",
		Port:            1515,
		DisplayID:       0,
		Pin:             "136300",
		MAC:             "B0:F2:F6:60:F7:43",
		LocalIP:         "192.168.1.66",
		TimeoutSeconds:  90,
		WaitForDownload: false,
		ImageFit:        ImageFitCover,
		CanvasWidth:     2560,
		CanvasHeight:    1440,
		CropX:           0.5,
		CropY:           0.65,
	}

	if err := SaveConfigToPath(path, want); err != nil {
		t.Fatal(err)
	}

	got, err := LoadConfigFromPath(path)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("LoadConfigFromPath() = %#v, want %#v", got, want)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if gotMode := info.Mode().Perm(); gotMode != 0o600 {
		t.Fatalf("config mode = %o, want 600", gotMode)
	}
}

func TestLoadConfigAppliesDefaultsToPartialFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{"host":"192.168.1.225","wait_for_download":false}`), 0o600); err != nil {
		t.Fatal(err)
	}

	config, err := LoadConfigFromPath(path)
	if err != nil {
		t.Fatal(err)
	}
	if config.Host != "192.168.1.225" {
		t.Fatalf("Host = %q", config.Host)
	}
	if config.Port != 1515 {
		t.Fatalf("Port = %d, want 1515", config.Port)
	}
	if config.TimeoutSeconds != 120 {
		t.Fatalf("TimeoutSeconds = %d, want 120", config.TimeoutSeconds)
	}
	if config.WaitForDownload {
		t.Fatal("WaitForDownload = true, want false")
	}
	if config.ImageFit != ImageFitOriginal {
		t.Fatalf("ImageFit = %q, want %q", config.ImageFit, ImageFitOriginal)
	}
	if config.CanvasWidth != 2560 || config.CanvasHeight != 1440 {
		t.Fatalf("canvas = %dx%d, want 2560x1440", config.CanvasWidth, config.CanvasHeight)
	}
}
