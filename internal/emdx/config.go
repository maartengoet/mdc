package emdx

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const (
	defaultConfigPort           = 1515
	defaultConfigTimeoutSeconds = 120
	defaultCanvasWidth          = 2560
	defaultCanvasHeight         = 1440
	defaultImageFit             = "original"
)

type Config struct {
	Host            string  `json:"host"`
	Port            int     `json:"port"`
	DisplayID       int     `json:"display_id"`
	Pin             string  `json:"pin"`
	MAC             string  `json:"mac"`
	LocalIP         string  `json:"local_ip"`
	TimeoutSeconds  int     `json:"timeout_seconds"`
	WaitForDownload bool    `json:"wait_for_download"`
	ImageFit        string  `json:"image_fit"`
	CanvasWidth     int     `json:"canvas_width"`
	CanvasHeight    int     `json:"canvas_height"`
	CropX           float64 `json:"crop_x"`
	CropY           float64 `json:"crop_y"`
}

func DefaultConfig() Config {
	return Config{
		Port:            defaultConfigPort,
		DisplayID:       0,
		TimeoutSeconds:  defaultConfigTimeoutSeconds,
		WaitForDownload: true,
		ImageFit:        defaultImageFit,
		CanvasWidth:     defaultCanvasWidth,
		CanvasHeight:    defaultCanvasHeight,
		CropX:           0.5,
		CropY:           0.5,
	}
}

func ConfigPath() (string, error) {
	if override := os.Getenv("MDC_CONFIG"); override != "" {
		return override, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".mdc", "config.json"), nil
}

func LoadConfig() (Config, error) {
	path, err := ConfigPath()
	if err != nil {
		return Config{}, err
	}
	return LoadConfigFromPath(path)
}

func LoadConfigFromPath(path string) (Config, error) {
	config := DefaultConfig()
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return config, nil
	}
	if err != nil {
		return Config{}, err
	}
	if err := json.Unmarshal(data, &config); err != nil {
		return Config{}, fmt.Errorf("read config %s: %w", path, err)
	}
	config.Normalize()
	return config, nil
}

func SaveConfig(config Config) error {
	path, err := ConfigPath()
	if err != nil {
		return err
	}
	return SaveConfigToPath(path, config)
}

func SaveConfigToPath(path string, config Config) error {
	config.Normalize()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}

	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return err
	}
	return os.Chmod(path, 0o600)
}

func (config *Config) Normalize() {
	if config.Port == 0 {
		config.Port = defaultConfigPort
	}
	if config.TimeoutSeconds == 0 {
		config.TimeoutSeconds = defaultConfigTimeoutSeconds
	}
	if config.ImageFit == "" {
		config.ImageFit = defaultImageFit
	}
	if config.CanvasWidth == 0 {
		config.CanvasWidth = defaultCanvasWidth
	}
	if config.CanvasHeight == 0 {
		config.CanvasHeight = defaultCanvasHeight
	}
	if config.DisplayID < 0 {
		config.DisplayID = 0
	}
	if config.DisplayID > 253 {
		config.DisplayID = 253
	}
	if config.CropX < 0 {
		config.CropX = 0
	}
	if config.CropX > 1 {
		config.CropX = 1
	}
	if config.CropY < 0 {
		config.CropY = 0
	}
	if config.CropY > 1 {
		config.CropY = 1
	}
}
