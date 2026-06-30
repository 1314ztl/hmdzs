export interface RouteInfo {
  name: string;
  param?: object;
}

export class NavRouter {
  static readonly KEY = 'navStack';

  static push(name: string, param?: object): void {
    const stack = AppStorage.get<RouteInfo[]>(NavRouter.KEY) ?? [];
    stack.push({ name, param });
    AppStorage.setOrCreate<RouteInfo[]>(NavRouter.KEY, stack);
  }

  static pop(): void {
    const stack = AppStorage.get<RouteInfo[]>(NavRouter.KEY) ?? [];
    if (stack.length > 0) {
      stack.pop();
      AppStorage.setOrCreate<RouteInfo[]>(NavRouter.KEY, stack);
    }
  }

  static clear(): void {
    AppStorage.setOrCreate<RouteInfo[]>(NavRouter.KEY, []);
  }

  static current(): RouteInfo | null {
    const stack = AppStorage.get<RouteInfo[]>(NavRouter.KEY) ?? [];
    return stack.length > 0 ? stack[stack.length - 1] : null;
  }

  static stack(): RouteInfo[] {
    return AppStorage.get<RouteInfo[]>(NavRouter.KEY) ?? [];
  }
}
