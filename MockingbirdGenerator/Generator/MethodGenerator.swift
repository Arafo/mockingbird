//
//  MethodGenerator.swift
//  MockingbirdCli
//
//  Created by Andrew Chang on 8/6/19.
//  Copyright © 2019 Bird Rides, Inc. All rights reserved.
//

// swiftlint:disable leading_whitespace

import Foundation

extension MethodParameter {
  func mockableTypeName(in context: MockableType, forClosure: Bool) -> String {
    let typeName = context.specializeTypeName(self.typeName)
    
    // When the type names are used for invocations instead of declaring the method parameters.
    guard forClosure else {
      return "\(typeName)"
    }
    
    if attributes.contains(.variadic) {
      return "[\(typeName.dropLast(3))]"
    } else {
      return "\(typeName)"
    }
  }
  
  var invocationName: String {
    let inoutAttribute = attributes.contains(.inout) ? "&" : ""
    let autoclosureForwarding = attributes.contains(.autoclosure) ? "()" : ""
    return "\(inoutAttribute)`\(name)`\(autoclosureForwarding)"
  }
  
  func matchableTypeName(in context: MockableType) -> String {
    let typeName = context.specializeTypeName(self.typeName).removingParameterAttributes()
    if attributes.contains(.variadic) {
      return "[" + typeName + "]"
    } else {
      return typeName
    }
  }
}

extension Method {
  func createGenerator(in context: MockableType) -> MethodGenerator {
    return MethodGenerator(method: self, context: context)
  }
}

class MethodGenerator {
  let method: Method
  let context: MockableType
  init(method: Method, context: MockableType) {
    self.method = method
    self.context = context
  }
  
  func generate() -> String {
    return [generatedMock,
            generatedStub,
            generatedVerification]
      .filter({ !$0.isEmpty })
      .joined(separator: "\n\n")
  }
  
  lazy var generatedMock: String = {
    if method.isInitializer {
      // We can't usually infer what concrete arguments to pass to the designated initializer.
      guard !method.attributes.contains(.convenience) else { return "" }
      
      let checkVersion: String
      if context.kind == .class {
        checkVersion = """
            super.init(\(superCallParameters))
            Mockingbird.checkVersion(for: self)
        """
      } else {
        checkVersion = "    Mockingbird.checkVersion(for: self)"
      }
      let genericConstraints = self.genericConstraints
      return """
        // MARK: Mockable `\(method.name)`
      
        public \(overridableModifiers)\(fullNameForMocking)\(genericConstraints) {
      \(checkVersion)
          let invocation = Mockingbird.Invocation(selectorName: "\(fullSelectorName)", arguments: [\(mockArgumentMatchers)])
          \(contextPrefix)mockingContext.didInvoke(invocation)
        \(stubbedImplementationCall)
        }
      """
    } else {
      return """
        // MARK: Mockable `\(method.name)`
      
        public \(overridableModifiers)func \(fullNameForMocking) \(returnTypeAttributes)-> \(specializedReturnTypeName)\(genericConstraints) {
          let invocation = Mockingbird.Invocation(selectorName: "\(fullSelectorName)", arguments: [\(mockArgumentMatchers)])
          \(contextPrefix)mockingContext.didInvoke(invocation)
      \(stubbedImplementationCall)
        }
      """
    }
  }()
  
  lazy var stubbableGenericTypesList: [String] = {
    let isGenericProtocol = context.kind == .protocol && !context.genericTypes.isEmpty
    let useMetatypeObject = method.kind.typeScope == .static || method.kind.typeScope == .class
    
    // The mock type name.
    let stubbedMockTypeName = context.stubbedMockName + (useMetatypeObject ? ".Type" : "")
    
    // The protocol that this mock is implementing or the class that it is subclassing.
    let mockedTypeName = !isGenericProtocol
      ? (!useMetatypeObject ? context.fullyQualifiedName : stubbedMockTypeName)
      : "Mockingbird.Mock.Protocol"
    
    return [mockedTypeName, stubbedMockTypeName]
  }()
  
  // Object used as the returned value of a stubbed implementation. Protocols that can only exist
  // as generic constraints return `Mockingbird.Mock.self` as an unusuable placeholder since it's
  // not possible to constrain a generic mock type to a generic prior return type.
  lazy var stubbableObject: String = {
    let isGenericProtocol = context.kind == .protocol && !context.genericTypes.isEmpty
    let useMetatypeObject = method.kind.typeScope == .static || method.kind.typeScope == .class
    return isGenericProtocol ? "Mockingbird.Mock.self" :
      (!useMetatypeObject ? "self" : (context.stubbedMockName + ".self"))
  }()
  
  lazy var generatedStub: String = {
    guard !method.isInitializer else { return "" }
    let parameterTypes = methodParameterTypes
    let returnTypeName = specializedReturnTypeName
    let invocationType = "(\(parameterTypes)) \(returnTypeAttributes)-> \(returnTypeName)"
    let stubbableGenericTypes = (stubbableGenericTypesList +
      [invocationType, returnTypeName]).joined(separator: ", ")
    let stub = """
      // MARK: Stubbable `\(method.name)`
    
      public \(regularModifiers)func \(fullNameForMatching) -> Mockingbird.Stubbable<\(stubbableGenericTypes)>\(genericConstraints) {
    \(matchableInvocation)
        if let stub = DispatchQueue.currentStub { \(contextPrefix)stubbingContext.swizzle(invocation, with: stub.implementation) }
        return Mockingbird.Stubbable<\(stubbableGenericTypes)>(object: \(stubbableObject), stubbingContext: \(contextPrefix)stubbingContext, invocation: invocation)
      }
    """
    guard isVariadicMethod else { return stub }
    
    // Allow methods with a variadic parameter to use variadics when stubbing.
    return """
    \(stub)
    
      public \(regularModifiers)func \(fullNameForMatchingVariadics) -> Mockingbird.Stubbable<\(stubbableGenericTypes)>\(genericConstraints) {
    \(matchableInvocationVariadics)
        if let stub = DispatchQueue.currentStub { \(contextPrefix)stubbingContext.swizzle(invocation, with: stub.implementation) }
        return Mockingbird.Stubbable<\(stubbableGenericTypes)>(object: \(stubbableObject), stubbingContext: \(contextPrefix)stubbingContext, invocation: invocation)
      }
    """
  }()
  
  lazy var generatedVerification: String = {
    guard !method.isInitializer else { return "" }
    let returnTypeName = specializedReturnTypeName
    let stub = """
      // MARK: Verifiable `\(method.name)`
    
      public \(regularModifiers)func \(fullNameForMatching) -> Mockingbird.Mockable<\(returnTypeName)>\(genericConstraints) {
    \(matchableInvocation)
        if let expectation = DispatchQueue.currentExpectation { expect(\(contextPrefix)mockingContext, handled: invocation, using: expectation) }
        return Mockingbird.Mockable<\(returnTypeName)>()
      }
    """
    guard isVariadicMethod else { return stub }
    
    // Allow methods with a variadic parameter to use variadics when verifying.
    return """
    \(stub)
    
      public \(regularModifiers)func \(fullNameForMatchingVariadics) -> Mockingbird.Mockable<\(returnTypeName)>\(genericConstraints) {
    \(matchableInvocationVariadics)
        if let expectation = DispatchQueue.currentExpectation { expect(\(contextPrefix)mockingContext, handled: invocation, using: expectation) }
        return Mockingbird.Mockable<\(returnTypeName)>()
      }
    """
  }()
  
  /// Modifiers specifically for stubbing and verification methods.
  lazy var regularModifiers: String = { return modifiers(allowOverride: false) }()
  /// Modifiers for mocked methods.
  lazy var overridableModifiers: String = { return modifiers(allowOverride: true) }()
  func modifiers(allowOverride: Bool = true) -> String {
    let isRequired = method.attributes.contains(.required)
    let required = (isRequired ? "required " : "")
    let override = (context.kind == .class && !isRequired && allowOverride ? "override " : "")
    let `static` = (method.kind.typeScope == .static || method.kind.typeScope == .class ? "static " : "")
    return "\(required)\(override)\(`static`)"
  }
  
  lazy var genericTypes: String = {
    return method.genericTypes.map({ $0.flattenedDeclaration }).joined(separator: ", ")
  }()
  
  lazy var genericConstraints: String = {
    guard !method.genericConstraints.isEmpty else { return "" }
    return " where " + method.genericConstraints.joined(separator: ", ")
  }()
  
  lazy var shortName: String = {
    guard let shortName = method.name.substringComponents(separatedBy: "(").first else {
      return method.name
    }
    let genericTypes = self.genericTypes
    return genericTypes.isEmpty ? "\(shortName)" : "\(shortName)<\(genericTypes)>"
  }()
  
  lazy var fullNameForMocking: String = {
    return fullName(forMatching: false, useVariadics: false)
  }()
  lazy var fullNameForMatching: String = {
    return fullName(forMatching: true, useVariadics: false)
  }()
  /// It's not possible to have an autoclosure with variadics. However, since a method can only have
  /// one variadic parameter, we can generate one method for wildcard matching using an argument
  /// matcher, and another for specific matching using variadics.
  lazy var fullNameForMatchingVariadics: String = {
    return fullName(forMatching: true, useVariadics: true)
  }()
  func fullName(forMatching: Bool, useVariadics: Bool) -> String {
    let parameterNames = method.parameters.map({ parameter -> String in
      let typeName: String
      if forMatching && (!useVariadics || !parameter.attributes.contains(.variadic)) {
        typeName = "@escaping @autoclosure () -> \(parameter.matchableTypeName(in: context))"
      } else {
        typeName = parameter.mockableTypeName(in: context, forClosure: false)
      }
      let argumentLabel = parameter.argumentLabel ?? "_"
      if argumentLabel != parameter.name {
        return "\(argumentLabel) \(parameter.name): \(typeName)"
      } else {
        return "\(parameter.name): \(typeName)"
      }
    })
    let failable: String
    if method.attributes.contains(.failable) {
      failable = "?"
    } else if method.attributes.contains(.unwrappedFailable) {
      failable = "!"
    } else {
      failable = ""
    }
    return "\(shortName)\(failable)(\(parameterNames.joined(separator: ", ")))"
  }
  
  lazy var fullSelectorName: String = {
    return "\(method.name) -> \(specializedReturnTypeName)"
  }()
  
  lazy var superCallParameters: String = {
    return method.parameters.map({ parameter -> String in
      let label = parameter.argumentLabel ?? parameter.name
      return "\(label): `\(parameter.name)`"
    }).joined(separator: ", ")
  }()
  
  lazy var stubbedImplementationCall: String = {
    let returnTypeName = specializedReturnTypeName
    let shouldReturn = !method.isInitializer && returnTypeName != "Void"
    let returnStatement = shouldReturn ? "return " : ""
    let tryInvocation = self.tryInvocation
    let implementationType = "(\(methodParameterTypes)) \(returnTypeAttributes)-> \(returnTypeName)"
    let optionalImplementation = shouldReturn ? "false" : "true"
    let typeCaster = shouldReturn ? "as!" : "as?"
    let invocationOptional = shouldReturn ? "" : "?"
    return """
        let implementation = \(contextPrefix)stubbingContext.implementation(for: invocation, optional: \(optionalImplementation))
        if let concreteImplementation = implementation as? \(implementationType) {
          \(returnStatement)\(tryInvocation)concreteImplementation(\(methodParameterNamesForInvocation))
        } else {
          \(returnStatement)\(tryInvocation)(implementation \(typeCaster) () -> \(returnTypeName))\(invocationOptional)()
        }
    """
  }()
  
  lazy var matchableInvocation: String = {
    guard !method.parameters.isEmpty else {
      return """
          let invocation = Mockingbird.Invocation(selectorName: "\(fullSelectorName)", arguments: [])
      """
    }
    return """
    \(resolvedArgumentMatchers)
        let invocation = Mockingbird.Invocation(selectorName: "\(fullSelectorName)", arguments: arguments)
    """
  }()
  
  lazy var matchableInvocationVariadics: String = {
    return """
    \(resolvedArgumentMatchersVariadics)
        let invocation = Mockingbird.Invocation(selectorName: "\(fullSelectorName)", arguments: arguments)
    """
  }()
  
  lazy var resolvedArgumentMatchers: String = {
    let resolved = method.parameters.map({
      return "Mockingbird.resolve(`\($0.name)`)"
    }).joined(separator: ", ")
    return "    let arguments = [\(resolved)]"
  }()
  
  /// Variadic parameters cannot be resolved indirectly using `resolve()`.
  lazy var resolvedArgumentMatchersVariadics: String = {
    let resolved = method.parameters.map({
      guard $0.attributes.contains(.variadic) else { return "Mockingbird.resolve(`\($0.name)`)" }
      // Directly create an ArgumentMatcher if this parameter is variadic.
      return "Mockingbird.ArgumentMatcher(`\($0.name)`)"
    }).joined(separator: ", ")
    return "    let arguments = [\(resolved)]"
  }()
  
  lazy var tryInvocation: String = {
    return method.attributes.contains(.throws) ? "try " : ""
  }()
  
  lazy var returnTypeAttributes: String = {
    let `throws` = method.attributes.contains(.throws) ? "throws " : ""
    let `rethrows` = method.attributes.contains(.rethrows) ? "rethrows " : ""
    return "\(`throws`)\(`rethrows`)"
  }()
  
  lazy var mockArgumentMatchers: String = {
    return method.parameters.map({ parameter -> String in
      // Can't save the parameter in the invocation because it's non-escaping
      guard !parameter.attributes.contains(.closure) || parameter.attributes.contains(.escaping)
        else { return "Mockingbird.ArgumentMatcher(nil)" }
      return "Mockingbird.ArgumentMatcher(`\(parameter.name)`)"
    }).joined(separator: ", ")
  }()
  
  lazy var contextPrefix: String = {
    return (method.kind.typeScope == .static || method.kind.typeScope == .class ? "staticMock." : "")
  }()
  
  lazy var specializedReturnTypeName: String = {
    return context.specializeTypeName(method.returnTypeName)
  }()
  
  lazy var methodParameterTypes: String = {
    return method.parameters
      .map({ $0.mockableTypeName(in: context, forClosure: true) })
      .joined(separator: ", ")
  }()
  
  lazy var methodParameterNamesForInvocation: String = {
    return method.parameters.map({ $0.invocationName }).joined(separator: ", ")
  }()
  
  lazy var isVariadicMethod: Bool = {
    return method.parameters.contains(where: { $0.attributes.contains(.variadic) })
  }()
}