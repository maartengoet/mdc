package emdx

import (
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"
)

func TestPrepareImageForDisplayCoverCreatesCanvas(t *testing.T) {
	sourcePath := writeTestJPEG(t, 4, 3)

	outputPath, cleanup, err := PrepareImageForDisplay(sourcePath, ImageTransformOptions{
		Fit:          ImageFitCover,
		CanvasWidth:  16,
		CanvasHeight: 9,
		CropX:        0.5,
		CropY:        0.5,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	if outputPath == sourcePath {
		t.Fatal("PrepareImageForDisplay returned original path for cover")
	}
	width, height := jpegSize(t, outputPath)
	if width != 16 || height != 9 {
		t.Fatalf("output size = %dx%d, want 16x9", width, height)
	}
}

func TestPrepareImageForDisplayContainCreatesCanvas(t *testing.T) {
	sourcePath := writeTestJPEG(t, 4, 3)

	outputPath, cleanup, err := PrepareImageForDisplay(sourcePath, ImageTransformOptions{
		Fit:          ImageFitContain,
		CanvasWidth:  16,
		CanvasHeight: 9,
		CropX:        0.5,
		CropY:        0.5,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	width, height := jpegSize(t, outputPath)
	if width != 16 || height != 9 {
		t.Fatalf("output size = %dx%d, want 16x9", width, height)
	}
}

func TestPrepareImageForDisplayOriginalReturnsInput(t *testing.T) {
	sourcePath := writeTestJPEG(t, 4, 3)

	outputPath, cleanup, err := PrepareImageForDisplay(sourcePath, ImageTransformOptions{Fit: ImageFitOriginal})
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()

	if outputPath != sourcePath {
		t.Fatalf("outputPath = %q, want %q", outputPath, sourcePath)
	}
}

func writeTestJPEG(t *testing.T, width, height int) string {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x * 40), G: uint8(y * 60), B: 120, A: 255})
		}
	}

	path := filepath.Join(t.TempDir(), "source.jpg")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := jpeg.Encode(file, img, nil); err != nil {
		_ = file.Close()
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	return path
}

func jpegSize(t *testing.T, path string) (int, int) {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()

	config, err := jpeg.DecodeConfig(file)
	if err != nil {
		t.Fatal(err)
	}
	return config.Width, config.Height
}
