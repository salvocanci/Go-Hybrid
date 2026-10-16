package regexbinding

import "testing"

// The Batch-H lesson, pinned: regex patterns cross as RAW strings — `\s`
// is not a hy escape. These tests cross into the real hyrt regex wrapper
// (pinned regex =1.11.1).

func TestIsMatchRawClasses(t *testing.T) {
	cases := []struct {
		pattern, text string
		want          bool
	}{
		{`\s+`, "   ", true},
		{`\s+`, "x", false},
		{`^\d{3}-\d{4}$`, "555-1234", true},
		{`^\d{3}-\d{4}$`, "5551234", false},
		{`^$`, "", true},
		{"b", "cat", false},
	}
	for _, c := range cases {
		got, err := IsMatch(c.pattern, c.text)
		if err != nil {
			t.Fatalf("IsMatch(%q, %q): %v", c.pattern, c.text, err)
		}
		if got != c.want {
			t.Fatalf("IsMatch(%q, %q) = %v, want %v", c.pattern, c.text, got, c.want)
		}
	}
}

func TestIsValid(t *testing.T) {
	if !IsValid(`a+\s?`) {
		t.Fatal("IsValid(a+\\s?) = false, want true")
	}
	if IsValid("(") {
		t.Fatal("IsValid(() = true, want false (unclosed group)")
	}
	if IsValid(`[a-`) {
		t.Fatal("IsValid([a-) = true, want false (bad class range)")
	}
}

func TestInvalidPatternErrors(t *testing.T) {
	// hyrt's is_match returns status -1 on a regex error; the binding
	// surfaces it as an error, never a silent false.
	if _, err := IsMatch("(", "x"); err == nil {
		t.Fatal("IsMatch with an invalid pattern must error")
	}
}
