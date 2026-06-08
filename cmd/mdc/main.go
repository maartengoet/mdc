package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/maartengoet/mdc/internal/emdx"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		printUsage()
		return nil
	}

	switch args[0] {
	case "show-image":
		return showImage(args[1:])
	case "set-content-url":
		return setContentURL(args[1:])
	case "info":
		return info(args[1:])
	case "battery":
		return battery(args[1:])
	case "auth":
		return auth(args[1:])
	case "wakeup":
		return wakeup(args[1:])
	case "config":
		return configCommand(args[1:])
	case "help", "-h", "--help":
		printUsage()
		return nil
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func showImage(args []string) error {
	config, err := emdx.LoadConfig()
	if err != nil {
		return err
	}

	flags := flag.NewFlagSet("show-image", flag.ExitOnError)
	host := flags.String("host", config.Host, "display IP address")
	port := flags.Int("port", config.Port, "MDC TCP port")
	display := flags.Int("display", config.DisplayID, "display ID")
	pin := flags.String("pin", config.Pin, "display PIN")
	mac := flags.String("mac", config.MAC, "optional display MAC address for Wake-on-LAN")
	image := flags.String("image", "", "image path")
	localIP := flags.String("local-ip", config.LocalIP, "local IP address advertised to the display")
	httpPort := flags.Int("http-port", 0, "local HTTP server port, or 0 for automatic")
	timeout := flags.Duration("timeout", time.Duration(config.TimeoutSeconds)*time.Second, "time to wait for image download")
	noWait := flags.Bool("no-wait", !config.WaitForDownload, "return after MDC command ACK instead of waiting for image download")
	imageFit := flags.String("fit", config.ImageFit, "image fit: original, contain, cover, or stretch")
	canvasWidth := flags.Int("canvas-width", config.CanvasWidth, "target display canvas width")
	canvasHeight := flags.Int("canvas-height", config.CanvasHeight, "target display canvas height")
	cropX := flags.Float64("crop-x", config.CropX, "horizontal crop/focus position from 0.0 to 1.0")
	cropY := flags.Float64("crop-y", config.CropY, "vertical crop/focus position from 0.0 to 1.0")
	if err := flags.Parse(args); err != nil {
		return err
	}
	displayID, err := displayIDFromFlag(*display)
	if err != nil {
		return err
	}
	if err := (emdx.ImageTransformOptions{
		Fit:          *imageFit,
		CanvasWidth:  *canvasWidth,
		CanvasHeight: *canvasHeight,
		CropX:        *cropX,
		CropY:        *cropY,
	}).Validate(); err != nil {
		return err
	}

	config.Host = *host
	config.Port = *port
	config.DisplayID = *display
	config.Pin = *pin
	config.MAC = *mac
	config.LocalIP = *localIP
	config.TimeoutSeconds = int(timeout.Seconds())
	config.WaitForDownload = !*noWait
	config.ImageFit = *imageFit
	config.CanvasWidth = *canvasWidth
	config.CanvasHeight = *canvasHeight
	config.CropX = *cropX
	config.CropY = *cropY
	if err := emdx.SaveConfig(config); err != nil {
		return err
	}

	options := emdx.ShowImageOptions{
		Host:         *host,
		Port:         *port,
		DisplayID:    displayID,
		Pin:          *pin,
		MAC:          *mac,
		ImagePath:    *image,
		LocalIP:      *localIP,
		HTTPPort:     *httpPort,
		Timeout:      *timeout,
		Wait:         !*noWait,
		ImageFit:     *imageFit,
		CanvasWidth:  *canvasWidth,
		CanvasHeight: *canvasHeight,
		CropX:        *cropX,
		CropY:        *cropY,
	}
	return emdx.ShowImage(context.Background(), options, func(message string) {
		fmt.Println(message)
	})
}

func setContentURL(args []string) error {
	config, err := emdx.LoadConfig()
	if err != nil {
		return err
	}

	flags := flag.NewFlagSet("set-content-url", flag.ExitOnError)
	host := flags.String("host", config.Host, "display IP address")
	port := flags.Int("port", config.Port, "MDC TCP port")
	display := flags.Int("display", config.DisplayID, "display ID")
	pin := flags.String("pin", config.Pin, "display PIN")
	url := flags.String("url", "", "content.json URL")
	if err := flags.Parse(args); err != nil {
		return err
	}
	displayID, err := displayIDFromFlag(*display)
	if err != nil {
		return err
	}

	config.Host = *host
	config.Port = *port
	config.DisplayID = *display
	config.Pin = *pin
	if err := emdx.SaveConfig(config); err != nil {
		return err
	}

	client := clientFromFlags(*host, *port, displayID, *pin)
	defer client.Close()
	if err := client.SetContentDownloadURL(*url); err != nil {
		return err
	}
	fmt.Println("content URL accepted")
	return nil
}

func info(args []string) error {
	config, err := emdx.LoadConfig()
	if err != nil {
		return err
	}

	flags := flag.NewFlagSet("info", flag.ExitOnError)
	host := flags.String("host", config.Host, "display IP address")
	port := flags.Int("port", config.Port, "MDC TCP port")
	display := flags.Int("display", config.DisplayID, "display ID")
	pin := flags.String("pin", config.Pin, "display PIN")
	if err := flags.Parse(args); err != nil {
		return err
	}
	displayID, err := displayIDFromFlag(*display)
	if err != nil {
		return err
	}

	config.Host = *host
	config.Port = *port
	config.DisplayID = *display
	config.Pin = *pin
	if err := emdx.SaveConfig(config); err != nil {
		return err
	}

	client := clientFromFlags(*host, *port, displayID, *pin)
	defer client.Close()

	if value, err := client.GetSerialNumber(); err == nil {
		fmt.Println("serial_number:", value)
	} else {
		fmt.Println("serial_number_error:", err)
	}
	if value, err := client.GetSoftwareVersion(); err == nil {
		fmt.Println("software_version:", value)
	} else {
		fmt.Println("software_version_error:", err)
	}
	if value, err := client.GetDeviceName(); err == nil {
		fmt.Println("device_name:", value)
	} else {
		fmt.Println("device_name_error:", err)
	}
	if value, err := client.GetPowerState(); err == nil {
		fmt.Println("power:", value)
	} else {
		fmt.Println("power_error:", err)
	}
	return nil
}

func battery(args []string) error {
	config, err := emdx.LoadConfig()
	if err != nil {
		return err
	}

	flags := flag.NewFlagSet("battery", flag.ExitOnError)
	host := flags.String("host", config.Host, "display IP address")
	port := flags.Int("port", config.Port, "MDC TCP port")
	display := flags.Int("display", config.DisplayID, "display ID")
	pin := flags.String("pin", config.Pin, "display PIN")
	if err := flags.Parse(args); err != nil {
		return err
	}
	displayID, err := displayIDFromFlag(*display)
	if err != nil {
		return err
	}

	config.Host = *host
	config.Port = *port
	config.DisplayID = *display
	config.Pin = *pin
	if err := emdx.SaveConfig(config); err != nil {
		return err
	}

	client := clientFromFlags(*host, *port, displayID, *pin)
	defer client.Close()
	state, err := client.GetBatteryState()
	if err != nil {
		return err
	}
	fmt.Println("battery_percent:", state.BatteryPercent)
	fmt.Println("plugged_in:", state.PluggedIn)
	fmt.Println("battery_warning_enabled:", state.BatteryWarningEnable)
	return nil
}

func auth(args []string) error {
	config, err := emdx.LoadConfig()
	if err != nil {
		return err
	}

	flags := flag.NewFlagSet("auth", flag.ExitOnError)
	host := flags.String("host", config.Host, "display IP address")
	port := flags.Int("port", config.Port, "MDC TCP port")
	display := flags.Int("display", config.DisplayID, "display ID")
	pin := flags.String("pin", config.Pin, "display PIN")
	if err := flags.Parse(args); err != nil {
		return err
	}
	displayID, err := displayIDFromFlag(*display)
	if err != nil {
		return err
	}

	config.Host = *host
	config.Port = *port
	config.DisplayID = *display
	config.Pin = *pin
	if err := emdx.SaveConfig(config); err != nil {
		return err
	}

	client := clientFromFlags(*host, *port, displayID, *pin)
	defer client.Close()
	if err := client.Connect(); err != nil {
		return err
	}
	fmt.Println("authenticated")
	return nil
}

func wakeup(args []string) error {
	config, err := emdx.LoadConfig()
	if err != nil {
		return err
	}

	flags := flag.NewFlagSet("wakeup", flag.ExitOnError)
	mac := flags.String("mac", config.MAC, "display MAC address")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *mac == "" {
		return fmt.Errorf("mac is required")
	}
	config.MAC = *mac
	if err := emdx.SaveConfig(config); err != nil {
		return err
	}
	if err := emdx.WakeOnLAN(*mac); err != nil {
		return err
	}
	fmt.Println("sent Wake-on-LAN packet to", *mac)
	return nil
}

func configCommand(args []string) error {
	if len(args) == 0 {
		args = []string{"show"}
	}

	switch args[0] {
	case "path":
		path, err := emdx.ConfigPath()
		if err != nil {
			return err
		}
		fmt.Println(path)
		return nil
	case "show":
		config, err := emdx.LoadConfig()
		if err != nil {
			return err
		}
		data, err := json.MarshalIndent(config, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(data))
		return nil
	case "set":
		return setConfig(args[1:])
	default:
		return fmt.Errorf("unknown config command %q", args[0])
	}
}

func setConfig(args []string) error {
	config, err := emdx.LoadConfig()
	if err != nil {
		return err
	}

	flags := flag.NewFlagSet("config set", flag.ExitOnError)
	host := flags.String("host", config.Host, "display IP address")
	port := flags.Int("port", config.Port, "MDC TCP port")
	display := flags.Int("display", config.DisplayID, "display ID")
	pin := flags.String("pin", config.Pin, "display PIN")
	mac := flags.String("mac", config.MAC, "display MAC address")
	localIP := flags.String("local-ip", config.LocalIP, "local IP address advertised to the display")
	timeout := flags.Duration("timeout", time.Duration(config.TimeoutSeconds)*time.Second, "time to wait for image download")
	waitForDownload := flags.Bool("wait-for-download", config.WaitForDownload, "wait for display to download image")
	imageFit := flags.String("fit", config.ImageFit, "image fit: original, contain, cover, or stretch")
	canvasWidth := flags.Int("canvas-width", config.CanvasWidth, "target display canvas width")
	canvasHeight := flags.Int("canvas-height", config.CanvasHeight, "target display canvas height")
	cropX := flags.Float64("crop-x", config.CropX, "horizontal crop/focus position from 0.0 to 1.0")
	cropY := flags.Float64("crop-y", config.CropY, "vertical crop/focus position from 0.0 to 1.0")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if _, err := displayIDFromFlag(*display); err != nil {
		return err
	}
	if err := (emdx.ImageTransformOptions{
		Fit:          *imageFit,
		CanvasWidth:  *canvasWidth,
		CanvasHeight: *canvasHeight,
		CropX:        *cropX,
		CropY:        *cropY,
	}).Validate(); err != nil {
		return err
	}

	config.Host = *host
	config.Port = *port
	config.DisplayID = *display
	config.Pin = *pin
	config.MAC = *mac
	config.LocalIP = *localIP
	config.TimeoutSeconds = int(timeout.Seconds())
	config.WaitForDownload = *waitForDownload
	config.ImageFit = *imageFit
	config.CanvasWidth = *canvasWidth
	config.CanvasHeight = *canvasHeight
	config.CropX = *cropX
	config.CropY = *cropY
	if err := emdx.SaveConfig(config); err != nil {
		return err
	}

	path, err := emdx.ConfigPath()
	if err != nil {
		return err
	}
	fmt.Println("saved config to", path)
	return nil
}

func clientFromFlags(host string, port int, displayID byte, pin string) *emdx.Client {
	return &emdx.Client{
		Host:      host,
		Port:      port,
		DisplayID: displayID,
		Pin:       pin,
		Timeout:   30 * time.Second,
	}
}

func displayIDFromFlag(display int) (byte, error) {
	if display < 0 || display > 253 {
		return 0, fmt.Errorf("display must be between 0 and 253")
	}
	return byte(display), nil
}

func printUsage() {
	fmt.Println(`Usage:
  mdc show-image --host IP --pin PIN --image PATH [--mac MAC]
  mdc set-content-url --host IP --pin PIN --url URL
  mdc auth --host IP --pin PIN
  mdc info --host IP --pin PIN
  mdc battery --host IP --pin PIN
  mdc wakeup --mac MAC
  mdc config [show|path]
  mdc config set [--host IP] [--pin PIN] [--mac MAC]

Common options:
  --host IP         display IP address, defaults to ~/.mdc/config.json
  --pin PIN         display PIN, defaults to ~/.mdc/config.json
  --port 1515       MDC TCP port, defaults to ~/.mdc/config.json
  --display 0       display ID, defaults to ~/.mdc/config.json

Show image options:
  --local-ip IP     local IP address exposed to the display
  --http-port N     local content server port, 0 means automatic
  --timeout D       download wait timeout, for example 120s
  --no-wait         return after MDC ACK
  --fit original    original, contain, cover, or stretch
  --canvas-width N  target display canvas width, default 2560
  --canvas-height N target display canvas height, default 1440
  --crop-x N        horizontal focus from 0.0 to 1.0
  --crop-y N        vertical focus from 0.0 to 1.0`)
}
