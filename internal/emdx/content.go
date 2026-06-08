package emdx

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type ManifestFile struct {
	ID        string
	FileName  string
	FileSize  int64
	ImageURL  string
	ProgramID string
}

func NewManifestFile(imagePath string, imageURL string) (ManifestFile, error) {
	info, err := os.Stat(imagePath)
	if err != nil {
		return ManifestFile{}, err
	}
	if info.IsDir() {
		return ManifestFile{}, fmt.Errorf("%s is a directory", imagePath)
	}

	id, err := newID()
	if err != nil {
		return ManifestFile{}, err
	}

	extension := strings.ToLower(filepath.Ext(imagePath))
	if extension == "" {
		extension = ".jpg"
	}

	return ManifestFile{
		ID:        id,
		FileName:  id + extension,
		FileSize:  info.Size(),
		ImageURL:  imageURL,
		ProgramID: "com.samsung.ios.ePaper",
	}, nil
}

func (file ManifestFile) JSON() ([]byte, error) {
	type content struct {
		ImageURL string `json:"image_url"`
		FileID   string `json:"file_id"`
		FilePath string `json:"file_path"`
		Duration int    `json:"duration"`
		FileSize string `json:"file_size"`
		FileName string `json:"file_name"`
	}
	type schedule struct {
		StartDate string    `json:"start_date"`
		StopDate  string    `json:"stop_date"`
		StartTime string    `json:"start_time"`
		Contents  []content `json:"contents"`
	}
	type manifest struct {
		Schedule    []schedule `json:"schedule"`
		Name        string     `json:"name"`
		Version     int        `json:"version"`
		CreateTime  string     `json:"create_time"`
		ID          string     `json:"id"`
		ProgramID   string     `json:"program_id"`
		ContentType string     `json:"content_type"`
		DeployType  string     `json:"deploy_type"`
	}

	body, err := json.Marshal(manifest{
		Schedule: []schedule{
			{
				StartDate: "1970-01-01",
				StopDate:  "2999-12-31",
				StartTime: "00:00:00",
				Contents: []content{
					{
						ImageURL: file.ImageURL,
						FileID:   file.ID,
						FilePath: "/home/owner/content/Downloads/vxtplayer/epaper/mobile/contents/" + file.ID + "/" + file.FileName,
						Duration: 91326,
						FileSize: fmt.Sprintf("%d", file.FileSize),
						FileName: file.FileName,
					},
				},
			},
		},
		Name:        "mdc",
		Version:     1,
		CreateTime:  "2025-01-01 00:00:00",
		ID:          file.ID,
		ProgramID:   file.ProgramID,
		ContentType: "ImageContent",
		DeployType:  "MOBILE",
	})
	if err != nil {
		return nil, err
	}

	return bytes.ReplaceAll(body, []byte("/"), []byte("\\/")), nil
}

func newID() (string, error) {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", err
	}
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	encoded := strings.ToUpper(hex.EncodeToString(bytes[:]))
	return fmt.Sprintf("%s-%s-%s-%s-%s",
		encoded[0:8],
		encoded[8:12],
		encoded[12:16],
		encoded[16:20],
		encoded[20:32],
	), nil
}
