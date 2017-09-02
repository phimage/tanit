import Foundation

import SwiftShell
import FileKit
import SwiftyJSON


// MARK: FileKit

extension Sequence where Self.Iterator.Element == Path {
    
    var commonAncestor: Path? {
        var iterator = self.makeIterator()
  
        var current = iterator.next()
        while current != nil {
            if let next = iterator.next() {
                current = current?.commonAncestor(next)
            }
        }
        return nil
    }

}

func zipCmd(_ zipFile: Path, _ files: [Path]) -> SwiftShell.RunOutput {
    var zipctx = CustomContext(main)
    if let ancestor = files.commonAncestor {
        zipctx.currentdirectory = ancestor.rawValue
    }
    return zipctx.run("/usr/bin/zip", "-rq", zipFile, files)
}

// MARK: Carthage

let guillemet = CharacterSet(charactersIn: "\"")

class CarthageBuild {
    
    var type: String
    var name: String
    var version: String

    init?(_ line: String) {
        var line = line
        if let rcomment = line.range(of: "#") { // remove comment
            line = line.substring(to: rcomment.lowerBound)
        }
        let array = line.components(separatedBy: " ")
        guard array.count > 1 else {
            return nil
        }
        self.type = array[0]
        self.name = array[1].trimmingCharacters(in: guillemet)
        if array.count > 2 {
            self.version = array[2].trimmingCharacters(in: guillemet)
        } else {
            self.version = ""
        }
    }
    
    var projectName: String {
        let folder = name.components(separatedBy: "/").last ?? "" /*bad: not safe*/
        return folder.replacingOccurrences(of: ".git", with: "")
    }
    
    var conf: CarthageBuild?
}

// MARK: Symbol, etc...

let parenthesis = CharacterSet(charactersIn: "()")
struct Dump {
    var uuid: String
    var arch: String
    var name: String
    
    init?(_ line: String) {
        let array = line.components(separatedBy: " ")
        guard array.count > 3 else {
            return nil
        }
        self.uuid = array[1]
        self.arch = array[2].trimmingCharacters(in: parenthesis)
        self.name = array[3].trimmingCharacters(in: guillemet)
    }
    
    var dSymPath: Path? { // xxx could be get at construction, just for test
        return dSym(for: uuid)
    }
}

func dump(for path: Path) -> [Dump]  {
    let result = main.run("dwarfdump", "--uuid", path)
    let lines = result.stdout.components(separatedBy: "\n")
    return lines.flatMap { Dump($0) }
}

func dSym(for uuid: String) -> Path?  {
    let result = main.run("mdfind", "\"com_apple_xcode_dsym_uuids == \(uuid)\"")
    let pathString = result.stdout
    let path = Path(pathString)
    if path.exists {
        return path
    }
    return nil
}

// MARK : Foundation
extension URL {
    /*static func + (url: URL, pathComponent: String) -> URL {
        return url.appendingPathComponent(pathComponent)
    }*/
    static func > (url: URL, pathComponent: String) -> URL {
        return url.appendingPathComponent(pathComponent, isDirectory: false)
    }
}
extension URL: RawRepresentable {
    public typealias RawValue = String
    public init?(rawValue: String) {
        self.init(string: rawValue)
    }
    public var rawValue: String {
        return self.absoluteString
    }
}

// File
extension TextFileStreamReader {
    var lines: [String] {
        var lines: [String] = []
        var current = self.nextLine()
        while let line = current {
            lines.append(line)
            current = self.nextLine()
        }
        return lines
    }
}

// MARK: Commander
import Commander

public protocol ArgumentRaw: ArgumentConvertible, RawRepresentable {}

public extension ArgumentRaw where RawValue == String {
    init(parser: ArgumentParser) throws {
        if let value = parser.shift() {
            if let value = Self(rawValue: value) {
                self = value
            } else {
                throw ArgumentError.invalidType(value: value, type: "\(Self.self)", argument: nil)
            }
        } else {
            throw ArgumentError.missingValue(argument: nil)
        }
    }
    var description: String {
        return self.rawValue
    }
}

enum Platform: String, ArgumentRaw {
    case macOS, iOS, tvOS
}

extension Path: ArgumentRaw {}
extension URL: ArgumentRaw {}


// MARK: Command
let cmd = command { (path: String, platform: Platform, outputPath: Path, url: URL) in
    
    if CommandLine.arguments.count < 4 {
        print("usage <project path> <platform> <output path> <base url>")
        exit(1)
    }

    let root = Path(path)
    if !root.isReadable {
        print("Unable to read \(root)")
        exit(EXIT_FAILURE)
    }

    if !outputPath.isWritable {
        print("Output path \(outputPath) is not writtable")
        exit(EXIT_FAILURE)
    }
 
    if url.scheme != "https" {
        print("URL scheme must be https: \(url)")
        exit(EXIT_FAILURE)
    }

    // common paths
    let cartfile = root + "Cartfile"
    let resolved = root + "Cartfile.resolved"
    let carthagePath = root + "Carthage"
    let buildPath = carthagePath + "Build"
    let platformPath = buildPath + platform.rawValue
    let checkoutsPath = carthagePath + "Checkouts"
    
    if !resolved.exists {
        print("\(resolved) not exist")
        exit(EXIT_FAILURE)
    }

    // Read resolved file for list of build
    guard let reader = TextFile(path: resolved).streamReader() else {
        print("Unable to read \(resolved)")
        exit(EXIT_FAILURE)
    }
    let builds = reader.lines.flatMap { CarthageBuild($0) }
    
    // Read carthage file for list of conf
    if let reader2 = TextFile(path: cartfile).streamReader() {
        let confs = reader2.lines.flatMap { CarthageBuild($0) }
        // Associate if possible
        for build in builds {
            for conf in confs {
                if conf.name == build.name {
                    build.conf = conf
                    break
                }
            }
            // TODO If not found, read cartfile in other checkout directories?
        }
    }
    
    var licenseFileNames = ["License.md", "LICENSE", "LICENSE.md", "LICENSE.txt"] // could do better by browsing files
    
    // Do a job for each build
    for build in builds {
        let projectName = build.projectName
        print("\(projectName)... ", terminator: "")
        let projectPath = platformPath + "\(projectName).framework"
        let projectDSYMPath = platformPath + "\(projectName).framework.dSYM"
        
        var files = [projectPath, projectDSYMPath]
        
        // Get symbol files
        if projectDSYMPath.exists {
            let uuids = dump(for: projectDSYMPath)
            
            let symbols: [Path] = uuids.flatMap {
                let path: Path = platformPath + "\($0.uuid).bcsymbolmap"
                
                if path.exists {
                    return path
                }
                return nil
            }
            files.append(contentsOf: symbols)
        }
        
        if let conf = build.conf {
            if build.version == "HEAD" {
                // do some stuff?, like add in json for HEAD...
            }
            
        }
        
        let checkoutsProjectPath = checkoutsPath + projectName
        
        // Find license file, and copy near frameworks
        let licenses = checkoutsProjectPath.find(searchDepth: 0) { // recursive?
            $0.rawValue.range(of: "license", options: .caseInsensitive) != nil
        }
        for licensePath in licenses {
            if licensePath.exists {
                // copie in platform path to have a better zip archive
                let licenseTempPath = platformPath + licensePath.fileName
                if licenseTempPath.exists {
                    try? licenseTempPath.deleteFile()
                }
                try? licensePath.copyFile(to: licenseTempPath)
                files.append(licenseTempPath)
            }
        }

        // TODO add others files, like doc or symbol
        //
        
        // Create output
        let outputProjectPath = outputPath + build.type + projectName + platform.rawValue + build.version
        
        try? outputProjectPath.createDirectory(withIntermediateDirectories: true)
        
        // Zip in it the framework
        let zipFile = outputProjectPath + "\(build.projectName).zip"
        if zipFile.exists {
            try? zipFile.deleteFile()
        }
        
        let zipResult = zipCmd(zipFile, files)
        if !zipResult.stdout.isEmpty {
            print(zipResult.stdout)
        }
        if !zipResult.stderror.isEmpty {
            print(zipResult.stderror)
        }
        
        print(zipFile.rawValue)
        
        // Create or update a json file for binary access
        let jsonPath = outputPath + "\(projectName).json"
        
        let textFile = TextFile(path: jsonPath)
        if !jsonPath.exists {
            try? textFile.write("{}")
        }
        let dataFile = DataFile(path: jsonPath)
        if let data = try? dataFile.read() {
            var json = JSON(data: data)
            let urlProject: URL = url + build.type + projectName + platform.rawValue + build.version > "\(build.projectName).zip"
            json[build.version].url = urlProject
            
            if let newData = try? json.rawData(options: [.prettyPrinted]) {
                try? dataFile.write(newData)
            }
        }
        print(try! textFile.read())
    }
}

cmd.run()



