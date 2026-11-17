import SwiftUI
import RealityKit
import Combine

struct GarageView: View {
    let onBack: () -> Void
    private var wallet: Wallet { Wallet.shared }
    @State private var tab = 0
    /// Что сейчас на подиуме: выбранное или то, что игрок смотрит перед покупкой.
    @State private var previewCar = Wallet.shared.car
    @State private var previewLivery = Wallet.shared.livery

    var body: some View {
        VStack(spacing: 14) {
            ScreenHeader(title: "Гараж", onBack: onBack) {
                CoinBalance(coins: wallet.coins)
            }

            GaragePreview(car: previewCar, livery: previewLivery)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Picker("", selection: $tab) {
                Text("Машины").tag(0)
                Text("Ливреи").tag(1)
            }
            .pickerStyle(.segmented)

            ScrollView {
                if tab == 0 {
                    VStack(spacing: 10) {
                        ForEach(CarModel.all) { car in carCard(car) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(Livery.all) { livery in liveryCard(livery) }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .background(Theme.garageBackground.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private func carCard(_ car: CarModel) -> some View {
        let selected = wallet.selectedCar == car.id
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(car.name).font(.system(size: 20, weight: .heavy, design: .rounded))
                Text(car.subtitle).font(.system(size: 12, weight: .medium)).opacity(0.75)
                StatBar(title: "Разгон", value: car.acceleration)
                StatBar(title: "Скорость", value: car.topSpeed)
                StatBar(title: "Сцепление", value: car.grip)
            }
            Spacer(minLength: 0)
            PurchaseButton(selected: selected, owned: wallet.owns(car: car), price: car.price,
                           canAfford: wallet.coins >= car.price) { wallet.buy(car: car) }
        }
        .padding(14)
        .background(Color.white.opacity(previewCar == car ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.white.opacity(0.7) : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { previewCar = car }
    }

    private func liveryCard(_ livery: Livery) -> some View {
        let selected = wallet.selectedLivery == livery.id
        return VStack(spacing: 8) {
            LiverySwatch(livery: livery)
            Text(livery.name).font(.system(size: 15, weight: .bold, design: .rounded))
            PurchaseButton(selected: selected, owned: wallet.owns(livery: livery), price: livery.price,
                           canAfford: wallet.coins >= livery.price) { wallet.buy(livery: livery) }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.white.opacity(previewLivery == livery ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.white.opacity(0.7) : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { previewLivery = livery }
    }
}
