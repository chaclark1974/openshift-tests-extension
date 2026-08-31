package example

import (
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("[sig-testing] hello world", func() {
	It("should print hello world", func() {
		message := "hello world"
		Expect(message).To(Equal("hello world"))
	})

	It("should verify greeting functionality", func() {
		greeting := getGreeting()
		Expect(greeting).To(ContainSubstring("hello"))
		Expect(greeting).To(ContainSubstring("world"))
	})
})

func getGreeting() string {
	return "hello world"
}
