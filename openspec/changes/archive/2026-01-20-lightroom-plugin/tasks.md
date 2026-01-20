# Tasks: Only35 Lightroom Plugin

## Phase 1: Foundation

### 1.1 Plugin Manifest
- [x] Create Info.lua with LrSdkVersion 13.0
- [x] Set LrSdkMinimumVersion = 10.0
- [x] Set LrToolkitIdentifier = 'com.only35.lightroom'
- [x] Register LrExportServiceProvider

### 1.2 Utilities Module
- [x] Create Only35Utils.lua
- [x] Define API_BASE_URL, WEB_BASE_URL constants
- [x] Define CLIENT_ID, REDIRECT_URI, SCOPES
- [x] Implement generateRandomString() for CSRF state

## Phase 2: Authentication

### 2.1 OAuth Module
- [x] Create Only35Auth.lua
- [x] Implement startOAuthFlow() - open browser, show code dialog
- [x] Implement exchangeCodeForTokens() - POST /oauth/token
- [x] Implement refreshAccessToken() - token refresh
- [x] Implement logout() - clear tokens, POST /oauth/revoke
- [x] Implement token storage in LrPrefs
- [x] Implement isTokenValid() with 60s buffer

## Phase 3: API Client

### 3.1 HTTP Client
- [x] Create Only35API.lua
- [x] Implement postJson() helper with auth headers
- [x] Implement get() helper with auth headers
- [x] Implement getUploadUrl() - POST /photographs/upload-url
- [x] Implement uploadToS3() - PUT to presigned URL
- [x] Implement createPhotograph() - POST /photographs
- [x] Implement updatePhotograph() - PATCH /photographs/{id}
- [x] Implement getRolls() - GET /rolls
- [x] Implement createRoll() - POST /rolls

## Phase 4: Publish Service

### 4.1 Service Provider
- [x] Create Only35PublishServiceProvider.lua
- [x] Implement processRenderedPhotos() - main upload loop
- [x] Implement getCollectionBehaviorInfo() - collection defaults
- [x] Implement metadataThatTriggersRepublish() - metadata triggers
- [x] Implement deletePhotosFromPublishedCollection()
- [x] Implement renamePublishedCollection()
- [x] Implement deletePublishedCollection()

### 4.2 UI Sections
- [x] Implement sectionsForTopOfDialog() - login UI
- [x] Implement viewForCollectionSettings() - roll selection
- [x] Implement startDialog() - initialize state

### 4.3 Metadata Mapping
- [x] Map rating (0-5) to stars
- [x] Map pickStatus to selected boolean
- [x] Map keywords to keywords array
- [x] Map caption to description
- [x] Map dateCreated to capturedAt
- [x] Map gps to location

### 4.4 Export Settings
- [x] Configure JPEG format, 92% quality
- [x] Configure max 4096x4096, longEdge resize
- [x] Configure sRGB color space
- [x] Configure screen sharpening level 2

## Phase 5: Error Handling & Polish

### 5.1 Error Handling
- [x] Add network error retry with backoff
- [x] Add API error parsing with user messages
- [x] Add S3 upload failure handling
- [x] Add rate limiting (Retry-After header)
- [x] Add token expiration auto-refresh

### 5.2 Distribution
- [x] Create .lrplugin package structure
- [x] Test via Plugin Manager > Add
- [x] Document installation process

## Dependencies

- Task 2.1 depends on 1.2 (Utils needed for constants)
- Task 3.1 depends on 2.1 (Auth needed for tokens)
- Task 4.1 depends on 3.1 (API needed for uploads)
- Task 4.2 depends on 4.1 (UI needs Service Provider)
- Task 4.3 depends on 4.1 (Metadata in processRenderedPhotos)
- Task 4.4 depends on 4.1 (Export settings in Service Provider)
- Task 5.1 depends on 4.1 (Error handling across modules)
- Task 5.2 depends on 5.1 (Distribution after complete)
