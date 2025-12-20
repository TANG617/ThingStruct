/*
 * FloatingActionButton.swift
 * Floating Action Button with Native Menu
 *
 * iOS native floating action button using SwiftUI Menu
 * Three fixed options:
 * - New State: Create a blank state
 * - From State Template: Pick a state template
 * - From Routine Template: Pick a routine template
 */

import SwiftUI
import SwiftData

// MARK: - Floating Action Button

@MainActor
struct FloatingActionButton: View {
    
    // MARK: - State
    
    @State private var showingAddState = false
    @State private var showingStateTemplatePicker = false
    @State private var showingRoutineTemplatePicker = false
    
    // MARK: - Body
    
    var body: some View {
        Menu {
            // New State
            Button {
                showingAddState = true
            } label: {
                Label("New State", systemImage: "plus.circle")
            }
            
            // From State Template
            Button {
                showingStateTemplatePicker = true
            } label: {
                Label("From State Template", systemImage: "doc.on.doc")
            }
            
        } label: {
            // Liquid Glass FAB Button
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 60, height: 60)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),
                                    .white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        }
        .menuStyle(.automatic)
        .sheet(isPresented: $showingAddState) {
            AddStateView()
        }
        .sheet(isPresented: $showingStateTemplatePicker) {
            StateTemplatePickerView()
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            HStack {
                Spacer()
                FloatingActionButton()
            }
        }
    }
    .modelContainer(for: [StateItem.self, StateTemplate.self, RoutineTemplate.self, ChecklistItem.self], inMemory: true)
}
