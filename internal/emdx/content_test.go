package emdx

import (
	"strings"
	"testing"
)

func TestManifestJSONEscapesSlashes(t *testing.T) {
	file := ManifestFile{
		ID:        "01234567-89AB-4DEF-8123-456789ABCDEF",
		FileName:  "01234567-89AB-4DEF-8123-456789ABCDEF.jpg",
		FileSize:  42,
		ImageURL:  "http://192.168.1.10:3000/image",
		ProgramID: "com.samsung.ios.ePaper",
	}

	body, err := file.JSON()
	if err != nil {
		t.Fatal(err)
	}
	text := string(body)
	if !strings.Contains(text, "http:\\/\\/192.168.1.10:3000\\/image") {
		t.Fatalf("expected escaped image URL in %s", text)
	}
	if !strings.Contains(text, "\"deploy_type\":\"MOBILE\"") {
		t.Fatalf("expected deploy type in %s", text)
	}
}
