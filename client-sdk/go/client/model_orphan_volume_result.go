/*
Copyright 2022 VMware, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package swagger

type OrphanVolumeResult struct {
	// The total orphan volumes returned.
	TotalOrphans int64 `json:"totalOrphans"`
	// This field is set only if includeDetails is set to true.
	TotalOrphansAttached int64 `json:"totalOrphansAttached,omitempty"`
	// This field is set only if includeDetails is set to true.
	TotalOrphansDetached int64 `json:"totalOrphansDetached,omitempty"`
	// Array of orphan volumes
	OrphanVolumes []OrphanVolume `json:"orphanVolumes"`
	// The time in minutes after which the next retry should be attempted to get the updated orphan volume list.
	RetryAfterMinutes int64 `json:"retryAfterMinutes"`
}
