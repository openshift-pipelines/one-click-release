package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"path/filepath"

	appstudiov1alpha1 "github.com/redhat-appstudio/application-api/api/v1alpha1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
)

func main() {
	var kubeconfig string
	var namespace string
	component := &appstudiov1alpha1.Component{}

	if home := homedir.HomeDir(); home != "" {
		flag.StringVar(
			&kubeconfig,
			"kubeconfig",
			filepath.Join(home, ".kube", "config"),
			"kubeconfig file",
		)
	} else {
		flag.StringVar(&kubeconfig, "kubeconfig", "", "kubeconfig file")
	}

	flag.StringVar(
		&namespace,
		"namespace",
		"tekton-ecosystem-tenant",
		"namespace containing Konflux components",
	)

	flag.Parse()

	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		log.Fatalf("failed to load kubeconfig: %v", err)
	}

	client, err := dynamic.NewForConfig(config)
	if err != nil {
		log.Fatalf("failed to create dynamic client: %v", err)
	}

	componentGVR := schema.GroupVersionResource{
		Group:    "appstudio.redhat.com",
		Version:  "v1alpha1",
		Resource: "components",
	}

	componentList, err := client.
		Resource(componentGVR).
		Namespace(namespace).
		List(context.Background(), metav1.ListOptions{})
	if err != nil {
		log.Fatalf("failed to list components: %v", err)
	}

	fmt.Printf("Found %d components\n\n", len(componentList.Items))

	for _, component := range componentList.Items {
		printComponent(component)
	}
}

func printComponent(component unstructured.Unstructured) {
	fmt.Printf("Name: %s\n", component.GetName())

	sourceURL, _, _ := unstructured.NestedString(
		component.Object,
		"spec",
		"source",
		"git",
		"url",
	)

	revision, _, _ := unstructured.NestedString(
		component.Object,
		"spec",
		"source",
		"git",
		"revision",
	)

	containerImage, _, _ := unstructured.NestedString(
		component.Object,
		"status",
		"lastPromotedImage",
	)

	if sourceURL != "" {
		fmt.Printf("Git URL: %s\n", sourceURL)
	}

	if revision != "" {
		fmt.Printf("Revision: %s\n", revision)
	}

	if containerImage != "" {
		fmt.Printf("Image: %s\n", containerImage)
	}

	fmt.Println("----------------------------------------")
}
