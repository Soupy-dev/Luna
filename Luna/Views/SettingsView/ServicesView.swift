//
//  ServicesView.swift
//  Sora
//
//  Created by Francesco on 09/08/25.
//

import SwiftUI
import Kingfisher

struct ServicesView: View {
    @StateObject private var serviceManager = ServiceManager.shared
    @StateObject private var stremioManager = StremioAddonManager.shared
    @Environment(\.editMode) private var editMode
    @State private var showDownloadAlert = false
    @State private var downloadURL = ""
    @State private var showServiceDownloadAlert = false
    @State private var autoUpdateEnabled: Bool = UserDefaults.standard.bool(forKey: "autoUpdateServicesEnabled")
    @State private var showStremioAddAlert = false
    @State private var stremioURL = ""
    @State private var stremioError: String?
    @State private var showStremioError = false
    
    var body: some View {
        ZStack {
            VStack {
                if serviceManager.services.isEmpty {
                    emptyStateView
                } else {
                    servicesList
                }
            }
            .navigationTitle("Services")
#if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editMode?.wrappedValue != .active {
                        Button {
                            showDownloadAlert = true
                        } label: {
                            Image(systemName: "plus.app")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation {
                            editMode?.wrappedValue =
                            (editMode?.wrappedValue == .active) ? .inactive : .active
                        }
                    } label: {
                        Image(systemName:
                                editMode?.wrappedValue == .active ? "checkmark" : "pencil")
                    }
                }
            }
#endif
            .refreshable {
                await serviceManager.updateServices()
            }
            .modifier(AddServiceInputModifier(
                isPresented: $showDownloadAlert,
                downloadURL: $downloadURL,
                onAdd: { downloadServiceFromURL() }
            ))
            .alert("Service Downloaded", isPresented: $showServiceDownloadAlert) {
                Button("OK") { }
            } message: {
                Text("The service has been successfully downloaded and saved to your documents folder.")
            }
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Services")
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var servicesList: some View {
        List {
            Section {
                Toggle("Auto-Update Services", isOn: $autoUpdateEnabled)
                    .onChange(of: autoUpdateEnabled) { newValue in
                        serviceManager.isAutoUpdateEnabled = newValue
                    }
            } footer: {
                Text("Automatically check for service updates when the app is opened.")
            }

            Section {
                ForEach(serviceManager.services, id: \.id) { service in
                    ServiceRow(service: service, serviceManager: serviceManager)
                }
                .onDelete(perform: deleteServices)
                .onMove { indices, newOffset in
                    serviceManager.moveServices(fromOffsets: indices, toOffset: newOffset)
                }
            }

            Section(header: stremioSectionHeader) {
                if stremioManager.addons.isEmpty {
                    Text("No Stremio addons installed")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(stremioManager.addons, id: \.id) { addon in
                        StremioAddonRow(addon: addon, manager: stremioManager)
                    }
                    .onDelete(perform: deleteStremioAddons)
                    .onMove { indices, newOffset in
                        stremioManager.moveAddons(fromOffsets: indices, toOffset: newOffset)
                    }
                }
            }
        }
        .modifier(AddStremioAddonInputModifier(
            isPresented: $showStremioAddAlert,
            addonURL: $stremioURL,
            onAdd: { addStremioAddon() }
        ))
        .alert("Stremio Error", isPresented: $showStremioError) {
            Button("OK", role: .cancel) { stremioError = nil }
        } message: {
            if let error = stremioError {
                Text(error)
            }
        }
    }

    @ViewBuilder
    private var stremioSectionHeader: some View {
        HStack {
            Text("Stremio Addons")
            Spacer()
            if editMode?.wrappedValue != .active {
                Button {
                    showStremioAddAlert = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
            }
        }
    }
    
    private func deleteServices(offsets: IndexSet) {
        for index in offsets {
            let service = serviceManager.services[index]
            serviceManager.removeService(service)
        }
    }

    private func deleteStremioAddons(offsets: IndexSet) {
        for index in offsets {
            let addon = stremioManager.addons[index]
            stremioManager.removeAddon(addon)
        }
    }

    private func addStremioAddon() {
        guard !stremioURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task {
            do {
                try await stremioManager.addAddon(from: stremioURL)
                await MainActor.run {
                    stremioURL = ""
                }
            } catch {
                await MainActor.run {
                    stremioError = error.localizedDescription
                    showStremioError = true
                }
            }
        }
    }
    
    private func downloadServiceFromURL() {
        guard !downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        Task {
            do {
                let wasHandled = await serviceManager.handlePotentialServiceURL(downloadURL)
                if wasHandled {
                    await MainActor.run {
                        downloadURL = ""
                        showServiceDownloadAlert = true
                    }
                }
            }
        }
    }
}


struct ServiceRow: View {
    let service: Service
    @ObservedObject var serviceManager: ServiceManager
    @State private var showingSettings = false
    
    private var isServiceActive: Bool {
        if let managedService = serviceManager.services.first(where: { $0.id == service.id }) {
            return managedService.isActive
        }
        return service.isActive
    }
    
    private var hasSettings: Bool {
        service.metadata.settings == true
    }
    
    var body: some View {
        HStack {
            KFImage(URL(string: service.metadata.iconUrl))
                .placeholder {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "app.dashed")
                                .foregroundColor(.secondary)
                        )
                }
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .padding(.trailing, 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(service.metadata.sourceName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Text(service.metadata.author.name)
                        .font(.caption)
                        .foregroundStyle(.gray)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    
                    Text(service.metadata.language)
                        .font(.caption)
                        .foregroundStyle(.gray)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    
                    Text("v\(service.metadata.version)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                if hasSettings {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if isServiceActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                serviceManager.setServiceState(service, isActive: !isServiceActive)
            }
        }
        .sheet(isPresented: $showingSettings) {
            ServiceSettingsView(service: service, serviceManager: serviceManager)
        }
    }
}

// MARK: - iOS 15 compatible Add Service input

private struct AddServiceInputModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var downloadURL: String
    var onAdd: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content
                .alert("Add Service", isPresented: $isPresented) {
                    TextField("JSON URL", text: $downloadURL)
                    Button("Cancel", role: .cancel) {
                        downloadURL = ""
                    }
                    Button("Add") {
                        onAdd()
                    }
                } message: {
                    Text("Enter the direct JSON file URL")
                }
        } else {
            content
                .sheet(isPresented: $isPresented) {
                    NavigationView {
                        Form {
                            Section {
                                TextField("JSON URL", text: $downloadURL)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } header: {
                                Text("Enter the direct JSON file URL")
                            }
                        }
                        .navigationTitle("Add Service")
                        #if !os(tvOS)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    downloadURL = ""
                                    isPresented = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") {
                                    isPresented = false
                                    onAdd()
                                }
                            }
                        }
                        #endif
                    }
                }
        }
    }
}

// MARK: - Stremio Addon Row

struct StremioAddonRow: View {
    let addon: StremioAddon
    @ObservedObject var manager: StremioAddonManager

    private var isAddonActive: Bool {
        if let managed = manager.addons.first(where: { $0.id == addon.id }) {
            return managed.isActive
        }
        return addon.isActive
    }

    var body: some View {
        HStack {
            if let logo = addon.manifest.logo, let logoURL = URL(string: logo) {
                KFImage(logoURL)
                    .placeholder {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "play.circle")
                                    .foregroundColor(.secondary)
                            )
                    }
                    .resizable()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .padding(.trailing, 10)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "play.circle")
                            .foregroundColor(.secondary)
                    )
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .padding(.trailing, 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(addon.manifest.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    if let version = addon.manifest.version {
                        Text("v\(version)")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }

                    if let desc = addon.manifest.description, !desc.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.gray)

                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isAddonActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                manager.setAddonState(addon, isActive: !isAddonActive)
            }
        }
    }
}

// MARK: - iOS 15 compatible Add Stremio Addon input

private struct AddStremioAddonInputModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var addonURL: String
    var onAdd: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content
                .alert("Add Stremio Addon", isPresented: $isPresented) {
                    TextField("Addon URL", text: $addonURL)
                    Button("Cancel", role: .cancel) {
                        addonURL = ""
                    }
                    Button("Add") {
                        onAdd()
                    }
                } message: {
                    Text("Enter the Stremio addon manifest URL")
                }
        } else {
            content
                .sheet(isPresented: $isPresented) {
                    NavigationView {
                        Form {
                            Section {
                                TextField("Addon URL", text: $addonURL)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } header: {
                                Text("Enter the Stremio addon manifest URL")
                            }
                        }
                        .navigationTitle("Add Stremio Addon")
                        #if !os(tvOS)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    addonURL = ""
                                    isPresented = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") {
                                    isPresented = false
                                    onAdd()
                                }
                            }
                        }
                        #endif
                    }
                }
        }
    }
}
