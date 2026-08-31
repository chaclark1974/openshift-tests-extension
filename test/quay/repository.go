package quay

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

type QuayRepository struct {
	Namespace      string `json:"namespace"`
	Name           string `json:"name"`
	Kind           string `json:"kind"`
	Description    string `json:"description"`
	IsPublic       bool   `json:"is_public"`
	IsOrganization bool   `json:"is_organization"`
	State          string `json:"state"`
}

var _ = Describe("[sig-registry] Quay public test repository", func() {
	It("should be accessible and return valid repository metadata", func() {
		const quayPublicTestRepo = "https://quay.io/api/v1/repository/quay/test"

		client := &http.Client{
			Timeout: 10 * time.Second,
		}

		resp, err := client.Get(quayPublicTestRepo)
		Expect(err).NotTo(HaveOccurred(), "Failed to connect to Quay public test repository")
		defer resp.Body.Close()

		Expect(resp.StatusCode).To(Equal(http.StatusOK),
			fmt.Sprintf("Expected 200 OK from Quay API, got %d", resp.StatusCode))

		Expect(resp.Header.Get("Content-Type")).To(ContainSubstring("application/json"),
			"Expected JSON response from Quay API")

		body, err := io.ReadAll(resp.Body)
		Expect(err).NotTo(HaveOccurred(), "Failed to read response body")

		var repo QuayRepository
		err = json.Unmarshal(body, &repo)
		Expect(err).NotTo(HaveOccurred(), "Failed to parse JSON response")

		Expect(repo.Namespace).To(Equal("quay"), "Repository namespace should be 'quay'")
		Expect(repo.Name).To(Equal("test"), "Repository name should be 'test'")
		Expect(repo.Kind).To(Equal("image"), "Repository kind should be 'image'")
		Expect(repo.IsPublic).To(BeTrue(), "Test repository should be public")
		Expect(repo.State).To(Equal("NORMAL"), "Repository state should be NORMAL")
	})
})
