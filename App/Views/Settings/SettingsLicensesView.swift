import SwiftUI

struct SettingsLicensesView: View {
    var body: some View {
        List {
            ForEach(Dependency.all) { dependency in
                Section {
                    Text(dependency.licenseText)
                        .font(.caption)
                        .monospaced()
                        .listRowBackground(Color.clear)
                } header: {
                    Text(dependency.name)
                }
            }
        }
        .listStyle(.grouped)
        .navigationTitle(String(localized: "Attributions", table: "More"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Dependency: Identifiable {
    let id: String
    let name: String
    let licenseText: String

    init(name: String, licenseText: String) {
        self.id = name
        self.name = name
        self.licenseText = licenseText
    }

    static let all: [Dependency] = [
        Dependency(
            name: "c2pa-swift",
            licenseText: """
            MIT License

            Copyright (c) 2025 Guardian Project

            Permission is hereby granted, free of charge, to any person obtaining a copy
            of this software and associated documentation files (the "Software"), to deal
            in the Software without restriction, including without limitation the rights
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            copies of the Software, and to permit persons to whom the Software is
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all
            copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            SOFTWARE.
            """
        ),
        Dependency(
            name: "SQLite.swift",
            licenseText: """
            Copyright (c) 2014-2015 Stephen Celis (<stephen@stephencelis.com>)

            Permission is hereby granted, free of charge, to any person obtaining a copy
            of this software and associated documentation files (the "Software"), to deal
            in the Software without restriction, including without limitation the rights
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            copies of the Software, and to permit persons to whom the Software is
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all
            copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            SOFTWARE.
            """
        ),
        Dependency(
            name: "swift-asn1",
            licenseText: """
            Copyright 2022 The SwiftASN1 Project

            The SwiftASN1 Project licenses this file to you under the Apache License,
            version 2.0 (the "License"); you may not use this file except in compliance
            with the License. You may obtain a copy of the License at:

              https://www.apache.org/licenses/LICENSE-2.0

            Unless required by applicable law or agreed to in writing, software
            distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
            WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
            License for the specific language governing permissions and limitations
            under the License.

            https://github.com/apple/swift-asn1
            """
        ),
        Dependency(
            name: "swift-certificates",
            licenseText: """
            Copyright 2022 The SwiftCertificates Project

            The SwiftCertificates Project licenses this file to you under the Apache License,
            version 2.0 (the "License"); you may not use this file except in compliance
            with the License. You may obtain a copy of the License at:

              https://www.apache.org/licenses/LICENSE-2.0

            Unless required by applicable law or agreed to in writing, software
            distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
            WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
            License for the specific language governing permissions and limitations
            under the License.

            https://github.com/apple/swift-certificates
            """
        ),
        Dependency(
            name: "swift-crypto",
            licenseText: """
            Copyright 2019 The SwiftCrypto Project

            The SwiftCrypto Project licenses this file to you under the Apache License,
            version 2.0 (the "License"); you may not use this file except in compliance
            with the License. You may obtain a copy of the License at:

              https://www.apache.org/licenses/LICENSE-2.0

            Unless required by applicable law or agreed to in writing, software
            distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
            WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
            License for the specific language governing permissions and limitations
            under the License.

            https://github.com/apple/swift-crypto
            """
        )
    ]
}
