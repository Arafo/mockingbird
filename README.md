# Mockingbird

[![Swift Package Manager](https://img.shields.io/badge/swift%20package%20manager-compatible-brightgreen.svg)](https://swift.org/package-manager/)

Mockingbird is a convenient mocking framework for Swift.

```swift
let bird = BirdMock()
given(bird.getCanFly()) ~> true     // Given the bird can fly
PalmTree(containing: bird).shake()  // When the palm tree is shaken
verify(bird.fly()).wasCalled()      // Then the bird flies away
```
---

## Installation

### Carthage

Add Mockingbird to your `Cartfile`.

```
github "birdrides/mockingbird" ~> 0.0.1
```

Then download and install the latest `Mockingbird.pkg` from [Releases](https://github.com/birdrides/mockingbird/releases).

### CocoaPods

CocoaPods support coming soon™

### Swift Package Manager

Add Mockingbird as a dependency in your `Package.swift` file.

```swift
dependencies: [
  .package(url: "https://github.com/birdrides/mockingbird.git", .upToNextMajor(from: "0.0.1"))
]
```

Then download and install the latest `Mockingbird.pkg` from [Releases](https://github.com/birdrides/mockingbird/releases).

### From Source

Clone the repository and build the `MockingbirdFramework` scheme for the desired platform. Drag the built 
`Mockingbird.framework` product into your project and link the library.

```bash
git clone https://github.com/birdrides/mockingbird.git
cd mockingbird
open Mockingbird.xcodeproj
```

Then install the Mockingbird command line interface.

```bash
make install
```

## Setup

Mockingbird generates mocks using the `mockingbird` command line tool which can be integrated into your
build process in many different ways.

### Automatic Integration

The Mockingbird CLI can automatically add a build step to generate mocks in the background whenever the 
specified targets are compiled.

```bash
mockingbird install --project <xcodeproj_path> --targets <comma_separated_targets>
```

### Manual Integration

Add a Run Script Phase to each target that needs generated mocks. Add See [Mockingbird CLI - Generate](#generate) 
for available generator options.

```bash
mockingbird generate &
```

## Usage

### Importing Mocks

By default, Mockingbird will generate target mocks into `Mockingbird/Mocks/` under the project’s source root 
directory. (Specify a custom location to generate mocks for each target using the `outputs` CLI option.)

Unit test targets that import a module with generated mocks should include the mocks file under Build Phases → 
Compile Sources.

![Build Phases → Compile Sources](Documentation/Assets/test-target-compile-sources.png)

### Mocking

Mockingbird adds the `Mock` suffix to mocks that it generates, providing the same methods, variables, and 
initializers as the original type. 

```swift
let bird = BirdMock()
``` 

### Stubbing

Stubbing allows you to define a custom value to return when a mocked method is called.

```swift
given(bird.createNest()) ~> Nest()
```

You can use an argument matcher to selectively return results. Stubs added later have precedence over those 
added earlier, so stubs with more generic argument matchers should be added first.

```swift
given(bird.chirp(volume: any())) ~> false     // Matches any volume
given(bird.chirp(volume: notNil())) ~> true   // Matches any non-nil volume
given(bird.chirp(volume: 10)) ~> false        // Matches volume = 10
```

Stub variables with their getter and setter methods.

```swift
given(bird.getName()) ~> "Big Bird"
given(bird.setName(any())) ~> { print($0) }
```

Getters can be stubbed to automatically save and return values.

```swift
given(bird.getLocation()) ~> lastSetValue(initial: nil)
bird.location = Location(name: "Hawaii")
assert(bird.location?.name == "Hawaii")
```

It’s possible to stub multiple methods with the same return type in a single call.

```swift
given(
  birdOne.getName(),
  birdTwo.getName()
) ~> "Big Bird"
```

### Verification

Mocks keep a record of invocations that it receives which can then be verified.

```swift
verify(bird.chirp(volume: 50)).wasCalled()
```

You can also conveniently verify multiple invocations at once (order doesn’t matter).

```swift
verify(
  bird.getName(),
  bird.chirp(volume: any()),
  bird.fly(to: notNil())
).wasCalled()
```

It’s possible to verify that an invocation was called a specific number of times with a call matcher.

```swift
verify(bird.getName()).wasNeverCalled()             // n = 0
verify(bird.getName()).wasCalled(exactly(10))       // n = 10
verify(bird.getName()).wasCalled(atLeast(10))       // n ≥ 10
verify(bird.getName()).wasCalled(atMost(10))        // n ≤ 10
verify(bird.getName()).wasCalled(between(5...10))   // 5 ≤ n ≤ 10
```

Call matchers support chaining and negation using logical operators.

```swift
verify(bird.getName()).wasCalled(not(exactly(10)))           // n ≠ 10
verify(bird.getName()).wasCalled(exactly(10).or(atMost(5)))  // n = 10 || n ≤ 5
```

Sometimes you need to perform custom checks on received parameters by using an argument captor.

```swift
let locationCaptor = ArgumentCaptor<Location>()
verify(bird.fly(to: locationCaptor)).wasCalled()
assert(locationCaptor.value?.name == "Hawaii")
```

You can test asynchronous code by using an `eventually` block which returns an `XCTestExpectation`. 

```swift
DispatchQueue.main.async {
  PalmTree(containing: bird).shake()
}
let expectation = eventually {
  verify(bird.fly()).wasCalled()
  verify(bird.chirp(volume: 50)).wasCalled()
}
wait(for: [expectation], timeout: 1.0)
```

Verifying doesn’t remove recorded invocations, so it’s safe to call verify multiple times (even if not recommended).

```swift
verify(bird.getName()).wasCalled()  // If this succeeds...
verify(bird.getName()).wasCalled()  // ...this also succeeds
```

### Resetting Mocks

Occasionally it’s necessary to remove stubs or clear recorded invocations.

```swift
reset(bird)                 // Removes all stubs and recorded invocations
clearStubs(on: bird)        // Only removes stubs
clearInvocations(on: bird)  // Only removes recorded invocations
```
 
## Mockingbird CLI

### Generate

Generate mocks for a set of targets in a project.

`mockingbird generate` 

| Option | Default Value | Description | 
| --- | --- | --- |
| `--project` | `$PROJECT_FILE_PATH` | Path to your project’s `.xcodeproj` file. |
| `--targets` | `$TARGET_NAME` | Comma-separated list of target names to mock. |
| `--srcroot` | `$SRCROOT` | The folder containing your project’s source files. |
| `--outputs` | `$MOCKINGBIRD_SRCROOT` | Comma-separated list of mock output file paths for each target. |
| `--preprocessor` | `nil` | Preprocessor expression to wrap all generated mocks in, e.g. `DEBUG`. |

| Flag | Description |
| --- | --- |
| `--disable-module-import` | Omit `@testable import <module>` from generated mocks. |
| `--only-protocols` | Only generate mocks for protocols. |

### Install

Starts automatically generating mocks by adding a custom Run Script Phase to each target.

`mockingbird install`

| Option | Default Value | Description |
| --- | --- | --- |
| `--project` | *(required)* | Your project’s `.xcodeproj` file. |
| `--targets` | *(required)* | Comma-separated list of target names to install the Run Script Phase. |
| `--srcroot` |  `<project>/../` | The folder containing your project’s source files. |
| `--outputs` | `$MOCKINGBIRD_SRCROOT` | Comma-separated list of mock output file paths for each target. |
| `--preprocessor` | `nil` | Preprocessor expression to wrap all generated mocks in, e.g. `DEBUG`. |

| Flag | Description |
| --- | --- |
| `--reinstall` | Overwrite existing Run Script Phases created by Mockingbird CLI. |
| `--synchronous` | Wait until mock generation completes before compiling target sources. |

### Uninstall

Stops automatically generating mocks.

`mockingbird uninstall`

| Option | Default Value | Description |
| --- | --- | --- |
| `--project` | *(required)* | Your project’s `.xcodeproj` file. |
| `--targets` | *(required)* | Comma-separated list of target names to uninstall the Run Script Phase. |
