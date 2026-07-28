package artifacts_registry

import (
	"context"
	"fmt"
	"os"

	"github.com/google/go-containerregistry/pkg/authn"
	"github.com/google/go-containerregistry/pkg/name"
	containerregistry "github.com/google/go-containerregistry/pkg/v1"
	"github.com/google/go-containerregistry/pkg/v1/remote"
)

type DockerHubArtifactsRegistry struct {
	registryURL    string
	repositoryName string
	auth           authn.Authenticator
}

var (
	dockerRegistryURLEnv            = "DOCKER_REGISTRY_URL"
	dockerRegistryRepositoryNameEnv = "DOCKER_REGISTRY_REPOSITORY_NAME"
	dockerRegistryUsernameEnv       = "DOCKER_REGISTRY_USERNAME"
	dockerRegistryPasswordEnv       = "DOCKER_REGISTRY_PASSWORD"
)

func NewDockerHubArtifactsRegistry() (*DockerHubArtifactsRegistry, error) {
	registryURL := os.Getenv(dockerRegistryURLEnv)
	if registryURL == "" {
		return nil, fmt.Errorf("%s environment variable is not set", dockerRegistryURLEnv)
	}

	repositoryName := os.Getenv(dockerRegistryRepositoryNameEnv)
	if repositoryName == "" {
		return nil, fmt.Errorf("%s environment variable is not set", dockerRegistryRepositoryNameEnv)
	}

	var auth authn.Authenticator = authn.Anonymous
	username := os.Getenv(dockerRegistryUsernameEnv)
	password := os.Getenv(dockerRegistryPasswordEnv)
	if username != "" && password != "" {
		auth = &authn.Basic{
			Username: username,
			Password: password,
		}
	}

	return &DockerHubArtifactsRegistry{
		registryURL:    registryURL,
		repositoryName: repositoryName,
		auth:           auth,
	}, nil
}

func (d *DockerHubArtifactsRegistry) GetTag(_ context.Context, _ string, buildId string) (string, error) {
	return fmt.Sprintf("%s/%s:%s", d.registryURL, d.repositoryName, buildId), nil
}

func (d *DockerHubArtifactsRegistry) GetImage(ctx context.Context, templateId string, buildId string, platform containerregistry.Platform) (containerregistry.Image, error) {
	imageURL, err := d.GetTag(ctx, templateId, buildId)
	if err != nil {
		return nil, fmt.Errorf("failed to get image URL: %w", err)
	}

	ref, err := name.ParseReference(imageURL)
	if err != nil {
		return nil, fmt.Errorf("invalid image reference: %w", err)
	}

	img, err := remote.Image(ref, remote.WithAuth(d.auth), remote.WithPlatform(platform), remote.WithContext(ctx))
	if err != nil {
		return nil, fmt.Errorf("error pulling image: %w", err)
	}

	return img, nil
}

func (d *DockerHubArtifactsRegistry) Delete(ctx context.Context, templateId string, buildId string) error {
	imageURL, err := d.GetTag(ctx, templateId, buildId)
	if err != nil {
		return fmt.Errorf("failed to get image URL: %w", err)
	}

	ref, err := name.ParseReference(imageURL)
	if err != nil {
		return fmt.Errorf("invalid image reference: %w", err)
	}

	err = remote.Delete(ref, remote.WithAuth(d.auth), remote.WithContext(ctx))
	if err != nil {
		// Many registries don't support delete — treat as non-fatal
		return fmt.Errorf("failed to delete image (may not be supported by registry): %w", err)
	}

	return nil
}
