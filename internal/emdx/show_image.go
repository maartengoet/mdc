package emdx

import (
	"context"
	"fmt"
	"mime"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type ShowImageOptions struct {
	Host         string
	Port         int
	DisplayID    byte
	Pin          string
	MAC          string
	ImagePath    string
	LocalIP      string
	HTTPPort     int
	Timeout      time.Duration
	Wait         bool
	ImageFit     string
	CanvasWidth  int
	CanvasHeight int
	CropX        float64
	CropY        float64
}

type ProgressFunc func(message string)

func ShowImage(ctx context.Context, options ShowImageOptions, progress ProgressFunc) error {
	if options.Timeout == 0 {
		options.Timeout = 120 * time.Second
	}
	if progress == nil {
		progress = func(string) {}
	}
	if err := validateImagePath(options.ImagePath); err != nil {
		return err
	}
	preparedImagePath, cleanupPreparedImage, err := PrepareImageForDisplay(options.ImagePath, ImageTransformOptions{
		Fit:          options.ImageFit,
		CanvasWidth:  options.CanvasWidth,
		CanvasHeight: options.CanvasHeight,
		CropX:        options.CropX,
		CropY:        options.CropY,
	})
	if err != nil {
		return err
	}
	defer cleanupPreparedImage()
	if preparedImagePath != options.ImagePath {
		progress("Prepared image for display")
	}

	localIP := options.LocalIP
	if localIP == "" {
		var err error
		localIP, err = LocalIPFor(options.Host, options.Port)
		if err != nil {
			return err
		}
	}

	server, contentURL, imageServed, err := startImageServer(preparedImagePath, localIP, options.HTTPPort)
	if err != nil {
		return err
	}
	defer server.Close()
	progress("Serving content at " + contentURL)

	if options.MAC != "" {
		progress("Sending Wake-on-LAN packet")
		if err := WakeOnLAN(options.MAC); err != nil {
			return err
		}
		time.Sleep(time.Second)
	}

	client := &Client{
		Host:      options.Host,
		Port:      options.Port,
		DisplayID: options.DisplayID,
		Pin:       options.Pin,
		Timeout:   30 * time.Second,
	}
	defer client.Close()

	progress("Connecting to display")
	if err := client.Connect(); err != nil {
		return err
	}

	progress("Sending content download command")
	if err := client.SetContentDownloadURL(contentURL); err != nil {
		return err
	}

	if !options.Wait {
		progress("Content command accepted")
		return nil
	}

	progress("Waiting for display to download the image")
	timer := time.NewTimer(options.Timeout)
	defer timer.Stop()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-imageServed:
		progress("Image downloaded by display")
		return nil
	case <-timer.C:
		return fmt.Errorf("timed out waiting for display to download image")
	}
}

type imageServer struct {
	*http.Server
	listener net.Listener
}

func (server imageServer) Close() {
	_ = server.Server.Close()
	_ = server.listener.Close()
}

func startImageServer(imagePath string, localIP string, requestedPort int) (imageServer, string, <-chan struct{}, error) {
	listener, err := net.Listen("tcp4", ":"+strconv.Itoa(requestedPort))
	if err != nil {
		return imageServer{}, "", nil, err
	}

	port := listener.Addr().(*net.TCPAddr).Port
	imageURL := "http://" + net.JoinHostPort(localIP, strconv.Itoa(port)) + "/image"
	manifestFile, err := NewManifestFile(imagePath, imageURL)
	if err != nil {
		_ = listener.Close()
		return imageServer{}, "", nil, err
	}
	contentJSON, err := manifestFile.JSON()
	if err != nil {
		_ = listener.Close()
		return imageServer{}, "", nil, err
	}

	imageServed := make(chan struct{})
	var imageServedOnce bool
	mux := http.NewServeMux()
	mux.HandleFunc("/content.json", func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write(contentJSON)
	})
	mux.HandleFunc("/image", func(response http.ResponseWriter, request *http.Request) {
		if contentType := mime.TypeByExtension(strings.ToLower(filepath.Ext(imagePath))); contentType != "" {
			response.Header().Set("Content-Type", contentType)
		}
		http.ServeFile(response, request, imagePath)
		if !imageServedOnce {
			imageServedOnce = true
			close(imageServed)
		}
	})

	server := imageServer{
		Server: &http.Server{
			Handler: mux,
		},
		listener: listener,
	}
	go func() {
		_ = server.Serve(listener)
	}()

	contentURL := "http://" + net.JoinHostPort(localIP, strconv.Itoa(port)) + "/content.json"
	return server, contentURL, imageServed, nil
}

func LocalIPFor(host string, port int) (string, error) {
	if port == 0 {
		port = defaultMDCPort
	}
	conn, err := net.Dial("udp4", net.JoinHostPort(host, strconv.Itoa(port)))
	if err == nil {
		defer conn.Close()
		if local, ok := conn.LocalAddr().(*net.UDPAddr); ok && local.IP != nil {
			return local.IP.String(), nil
		}
	}

	interfaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}
	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if !ok {
				continue
			}
			ip := ipNet.IP.To4()
			if ip != nil && !ip.IsLoopback() {
				return ip.String(), nil
			}
		}
	}
	return "", fmt.Errorf("could not determine local IP address")
}

func validateImagePath(path string) error {
	if path == "" {
		return fmt.Errorf("image path is required")
	}
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if info.IsDir() {
		return fmt.Errorf("%s is a directory", path)
	}
	switch strings.ToLower(filepath.Ext(path)) {
	case ".jpg", ".jpeg", ".png", ".bmp":
		return nil
	default:
		return fmt.Errorf("unsupported image type %q; expected jpg, jpeg, png, or bmp", filepath.Ext(path))
	}
}
