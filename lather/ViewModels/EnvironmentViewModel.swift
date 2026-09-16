import Foundation
import Observation

@Observable
final class EnvironmentViewModel {
    var environments: [APIEnvironment]
    var activeEnvironmentID: APIEnvironment.ID?

    private let vault: VaultManager?

    /// `vault` is optional so previews/tests can keep constructing this
    /// in-memory-only, with no persistence.
    init(vault: VaultManager? = nil) {
        self.vault = vault
        if let file = vault?.loadEnvironmentsFile() {
            self.environments = file.environments
            self.activeEnvironmentID = file.activeEnvironmentID
        } else {
            self.environments = []
            self.activeEnvironmentID = nil
        }
    }

    /// The active environment's variables flattened for substitution —
    /// empty (not an error) when nothing's selected.
    var activeVariables: [String: String] {
        guard let activeEnvironmentID, let environment = environments.first(where: { $0.id == activeEnvironmentID }) else {
            return [:]
        }
        var result: [String: String] = [:]
        for variable in environment.variables where !variable.key.isEmpty {
            result[variable.key] = variable.value
        }
        return result
    }

    private var persistTask: Task<Void, Never>?

    /// Debounced so rapid edits (typing a variable's value) collapse into a
    /// single disk write shortly after things go quiet — same idea as
    /// `SidebarViewModel.persist()`.
    private func persist() {
        persistTask?.cancel()
        guard let vault else { return }
        let file = VaultManager.EnvironmentsFile(environments: environments, activeEnvironmentID: activeEnvironmentID)
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            vault.saveEnvironmentsFile(file)
        }
    }

    /// Writes immediately, bypassing the debounce — call before anything
    /// that could end the session.
    func flushPendingChanges() {
        persistTask?.cancel()
        vault?.saveEnvironmentsFile(VaultManager.EnvironmentsFile(environments: environments, activeEnvironmentID: activeEnvironmentID))
    }

    func createEnvironment(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let environment = APIEnvironment(name: trimmedName)
        environments.append(environment)
        if activeEnvironmentID == nil {
            activeEnvironmentID = environment.id
        }
        persist()
    }

    func renameEnvironment(_ id: APIEnvironment.ID, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let index = environments.firstIndex(where: { $0.id == id }) else { return }
        environments[index].name = trimmedName
        persist()
    }

    func deleteEnvironment(_ id: APIEnvironment.ID) {
        environments.removeAll { $0.id == id }
        if activeEnvironmentID == id {
            activeEnvironmentID = environments.first?.id
        }
        persist()
    }

    func setActiveEnvironment(_ id: APIEnvironment.ID?) {
        activeEnvironmentID = id
        persist()
    }

    func addVariable(to environmentID: APIEnvironment.ID) {
        guard let index = environments.firstIndex(where: { $0.id == environmentID }) else { return }
        environments[index].variables.append(EnvironmentVariable())
        persist()
    }

    func updateVariable(_ variableID: EnvironmentVariable.ID, in environmentID: APIEnvironment.ID, key: String, value: String) {
        guard let environmentIndex = environments.firstIndex(where: { $0.id == environmentID }),
              let variableIndex = environments[environmentIndex].variables.firstIndex(where: { $0.id == variableID })
        else { return }
        environments[environmentIndex].variables[variableIndex].key = key
        environments[environmentIndex].variables[variableIndex].value = value
        persist()
    }

    func removeVariable(_ variableID: EnvironmentVariable.ID, from environmentID: APIEnvironment.ID) {
        guard let environmentIndex = environments.firstIndex(where: { $0.id == environmentID }) else { return }
        environments[environmentIndex].variables.removeAll { $0.id == variableID }
        persist()
    }
}
