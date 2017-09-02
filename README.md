
# tanit
[<img align="left" src="https://upload.wikimedia.org/wikipedia/commons/d/de/Tanit-Symbol-alternate.svg" hspace="20">](#logo)
Command line utility to create zip archives of frameworks produced by the dependency manager [Carthage](https://github.com/Carthage/Carthage)

These archives could be used as binary source for [Carthage/archive-prebuilt-frameworks](https://github.com/Carthage/Carthage#archive-prebuilt-frameworks-into-one-zip-file)

 - tanit parse your `Cartfile.resolved` file, create one zip and one json file for each frameworks

    - the zip contains the framework, the license file and symbole files
    - the json follow the format defined by [Carthage/binary-project-specification](https://github.com/Carthage/Carthage/blob/master/Documentation/Artifacts.md#example-binary-project-specification), to define the zip path for the current framework version


## Install

tanit use [Marathon](https://github.com/JohnSundell/Marathon) to checkout dependencies and run.

You can install tanit by typing

```
marathon install phimage/tanit
```

Or you can clone repository and launch
```
$ git clone https://github.com/phimage/tanit.git
```
or then do a `marathon update`, `marathon install`

## Usage

```
$ tanit --help
Usage:

    $ tanit <path> <platform> <output> <url>

Arguments:

    path - Path of your project
    platform - Platform. One of iOS, macOS, tvOS
    output - Output folder
    url - URL used for JSON output

Options:
    --verbose [default: false]
    --quiet [default: false]
```

## Why `tanit`?

Tanit was a Berber Punic and Phoenician goddess, the chief deity of Carthage alongside her consort Ba`al Hammon [Wikipedia](https://en.wikipedia.org/wiki/Tanit)
