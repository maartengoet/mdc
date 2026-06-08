package emdx

import (
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	_ "image/png"
	"math"
	"os"
	"path/filepath"
	"strings"
)

const (
	ImageFitOriginal = "original"
	ImageFitContain  = "contain"
	ImageFitCover    = "cover"
	ImageFitStretch  = "stretch"
)

type ImageTransformOptions struct {
	Fit          string
	CanvasWidth  int
	CanvasHeight int
	CropX        float64
	CropY        float64
}

func (options *ImageTransformOptions) Normalize() {
	if options.Fit == "" {
		options.Fit = ImageFitOriginal
	}
	if options.CanvasWidth == 0 {
		options.CanvasWidth = defaultCanvasWidth
	}
	if options.CanvasHeight == 0 {
		options.CanvasHeight = defaultCanvasHeight
	}
	if options.CropX < 0 {
		options.CropX = 0
	}
	if options.CropX > 1 {
		options.CropX = 1
	}
	if options.CropY < 0 {
		options.CropY = 0
	}
	if options.CropY > 1 {
		options.CropY = 1
	}
}

func (options ImageTransformOptions) Validate() error {
	options.Normalize()
	switch options.Fit {
	case ImageFitOriginal, ImageFitContain, ImageFitCover, ImageFitStretch:
	default:
		return fmt.Errorf("unsupported image fit %q; expected original, contain, cover, or stretch", options.Fit)
	}
	if options.CanvasWidth <= 0 || options.CanvasHeight <= 0 {
		return fmt.Errorf("canvas must be larger than zero")
	}
	return nil
}

func PrepareImageForDisplay(imagePath string, options ImageTransformOptions) (string, func(), error) {
	options.Normalize()
	if err := options.Validate(); err != nil {
		return "", nil, err
	}
	if options.Fit == ImageFitOriginal {
		return imagePath, func() {}, nil
	}

	switch strings.ToLower(filepath.Ext(imagePath)) {
	case ".jpg", ".jpeg", ".png":
	default:
		return "", nil, fmt.Errorf("image fit %q supports jpg, jpeg, and png input", options.Fit)
	}

	input, err := os.Open(imagePath)
	if err != nil {
		return "", nil, err
	}
	defer input.Close()

	src, _, err := image.Decode(input)
	if err != nil {
		return "", nil, err
	}

	rendered, err := renderToCanvas(src, options)
	if err != nil {
		return "", nil, err
	}

	output, err := os.CreateTemp("", "mdc-display-*.jpg")
	if err != nil {
		return "", nil, err
	}
	outputPath := output.Name()
	if err := jpeg.Encode(output, rendered, &jpeg.Options{Quality: 95}); err != nil {
		_ = output.Close()
		_ = os.Remove(outputPath)
		return "", nil, err
	}
	if err := output.Close(); err != nil {
		_ = os.Remove(outputPath)
		return "", nil, err
	}

	return outputPath, func() {
		_ = os.Remove(outputPath)
	}, nil
}

func renderToCanvas(src image.Image, options ImageTransformOptions) (*image.RGBA, error) {
	srcRGBA := rgbaImage(src)
	srcWidth := srcRGBA.Bounds().Dx()
	srcHeight := srcRGBA.Bounds().Dy()
	if srcWidth == 0 || srcHeight == 0 {
		return nil, fmt.Errorf("image has empty bounds")
	}

	canvas := image.NewRGBA(image.Rect(0, 0, options.CanvasWidth, options.CanvasHeight))
	draw.Draw(canvas, canvas.Bounds(), &image.Uniform{C: color.White}, image.Point{}, draw.Src)

	switch options.Fit {
	case ImageFitContain:
		scale := math.Min(float64(options.CanvasWidth)/float64(srcWidth), float64(options.CanvasHeight)/float64(srcHeight))
		scaledWidth := float64(srcWidth) * scale
		scaledHeight := float64(srcHeight) * scale
		offsetX := (float64(options.CanvasWidth) - scaledWidth) * options.CropX
		offsetY := (float64(options.CanvasHeight) - scaledHeight) * options.CropY
		fillScaled(canvas, srcRGBA, scale, scale, 0, 0, offsetX, offsetY, scaledWidth, scaledHeight)
	case ImageFitCover:
		scale := math.Max(float64(options.CanvasWidth)/float64(srcWidth), float64(options.CanvasHeight)/float64(srcHeight))
		scaledWidth := float64(srcWidth) * scale
		scaledHeight := float64(srcHeight) * scale
		offsetX := (scaledWidth - float64(options.CanvasWidth)) * options.CropX
		offsetY := (scaledHeight - float64(options.CanvasHeight)) * options.CropY
		fillScaled(canvas, srcRGBA, scale, scale, offsetX, offsetY, 0, 0, float64(options.CanvasWidth), float64(options.CanvasHeight))
	case ImageFitStretch:
		scaleX := float64(options.CanvasWidth) / float64(srcWidth)
		scaleY := float64(options.CanvasHeight) / float64(srcHeight)
		fillScaled(canvas, srcRGBA, scaleX, scaleY, 0, 0, 0, 0, float64(options.CanvasWidth), float64(options.CanvasHeight))
	default:
		return nil, fmt.Errorf("unsupported image fit %q", options.Fit)
	}

	return canvas, nil
}

func rgbaImage(src image.Image) *image.RGBA {
	if rgba, ok := src.(*image.RGBA); ok && rgba.Bounds().Min == (image.Point{}) {
		return rgba
	}
	bounds := src.Bounds()
	rgba := image.NewRGBA(image.Rect(0, 0, bounds.Dx(), bounds.Dy()))
	draw.Draw(rgba, rgba.Bounds(), src, bounds.Min, draw.Src)
	return rgba
}

func fillScaled(dst *image.RGBA, src *image.RGBA, scaleX, scaleY, sourceOffsetX, sourceOffsetY, destX, destY, width, height float64) {
	minX := maxInt(0, int(math.Floor(destX)))
	minY := maxInt(0, int(math.Floor(destY)))
	maxX := minInt(dst.Bounds().Dx(), int(math.Ceil(destX+width)))
	maxY := minInt(dst.Bounds().Dy(), int(math.Ceil(destY+height)))

	for y := minY; y < maxY; y++ {
		srcY := (float64(y)-destY+sourceOffsetY+0.5)/scaleY - 0.5
		for x := minX; x < maxX; x++ {
			srcX := (float64(x)-destX+sourceOffsetX+0.5)/scaleX - 0.5
			r, g, b, a := sampleBilinear(src, srcX, srcY)
			i := dst.PixOffset(x, y)
			dst.Pix[i+0] = r
			dst.Pix[i+1] = g
			dst.Pix[i+2] = b
			dst.Pix[i+3] = a
		}
	}
}

func sampleBilinear(src *image.RGBA, x, y float64) (uint8, uint8, uint8, uint8) {
	width := src.Bounds().Dx()
	height := src.Bounds().Dy()
	x = clampFloat(x, 0, float64(width-1))
	y = clampFloat(y, 0, float64(height-1))

	x0 := int(math.Floor(x))
	y0 := int(math.Floor(y))
	x1 := minInt(x0+1, width-1)
	y1 := minInt(y0+1, height-1)
	fx := x - float64(x0)
	fy := y - float64(y0)

	r00, g00, b00, a00 := rgbaAt(src, x0, y0)
	r10, g10, b10, a10 := rgbaAt(src, x1, y0)
	r01, g01, b01, a01 := rgbaAt(src, x0, y1)
	r11, g11, b11, a11 := rgbaAt(src, x1, y1)

	return lerp2D(r00, r10, r01, r11, fx, fy),
		lerp2D(g00, g10, g01, g11, fx, fy),
		lerp2D(b00, b10, b01, b11, fx, fy),
		lerp2D(a00, a10, a01, a11, fx, fy)
}

func rgbaAt(src *image.RGBA, x, y int) (float64, float64, float64, float64) {
	i := src.PixOffset(x, y)
	return float64(src.Pix[i+0]), float64(src.Pix[i+1]), float64(src.Pix[i+2]), float64(src.Pix[i+3])
}

func lerp2D(v00, v10, v01, v11, fx, fy float64) uint8 {
	top := v00 + (v10-v00)*fx
	bottom := v01 + (v11-v01)*fx
	return uint8(math.Round(top + (bottom-top)*fy))
}

func clampFloat(value, minValue, maxValue float64) float64 {
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
