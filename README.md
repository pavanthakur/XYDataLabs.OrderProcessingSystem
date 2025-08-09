# TestAppXY_OrderProcessingSystem

<!---
# 🔥 Attention!!

**Currently, CleanArchitecture with below features mentioned are covered in this project. 

Note : Logs can be checked inside TestAppXY_OrderProcessingSystem\logs\ folder.
-->

# Certificate were generated with below commands
Q:\GIT\TestAppXY_OrderProcessingSystem> dotnet dev-certs https -ep ./dev-certs/aspnetapp.pfx -p P@ss100
Q:\GIT\TestAppXY_OrderProcessingSystem> dotnet dev-certs https --trust

# 🏃‍♂️ How to Run the Project
  1. First make sure that you have **.NET 8.0** and **Visual Studio 2022** are installed.
  2. Now open the solution with VS 2022 and build the solution to make sure that there is no error.
  3. Now choose either of http or https or Docker profile as startup project and then run it. On startup necessary databases will be created in **MSSQLLocalDB**. Along with seed data.
     Note : change sql server IP Address, username and password
  4. Start the project using the PowerShell automation script with environment-specific configurations:
      # Development environment
      Q:\GIT\TestAppXY_OrderProcessingSystem> .\start-docker.ps1 -Environment dev -Profile http
      
      # UAT environment  
      Q:\GIT\TestAppXY_OrderProcessingSystem> .\start-docker.ps1 -Environment uat -Profile https
      
      # Production environment
      Q:\GIT\TestAppXY_OrderProcessingSystem> .\start-docker.ps1 -Environment prod -Profile https -CleanCache
  5. Ensure in Windows Docker Desktop Container "testappxy_orderprocessingsystem" with API and UI Images are loaded. Ensure ports for http and https are correct as below
     Test the APIs using Swagger for all the business use cases.
     i) a. For Docker profile to start API with https -> https://localhost:5001/swagger/index.html
	    b. For Docker profile to start UI with https -> https://localhost:5003/
	 OR
	 ii) a. For Docker profile to start API with http -> http://localhost:5000/swagger/index.html
	     b. For Docker profile to start UI with http -> http://localhost:5002/
	 
   6. To Debug  API with Docker from VS2022
       Debug > AttachToProcess
	   Connection type : Docker (Linux Container)
	   Contaier target : testappxy_orderprocessingsystem-api-1
	   Attach To : XYDataLabs.OrderProcessingSystem.API
	   Code type : Managed (.Net Core for Unix) code
	   (Note : Ensure Debug > Windows > Modules - Symbols are loaded for XYDataLabs.OrderProcessingSystem.API)
   
   7. Open Q:\GIT\TestAppXY_OrderProcessingSystem in VSCode
      To Debug UI application :- Use Run and Debug > Launch Chrome (UI 5003)
	  
# Clean Architecture in ASP.NET Core
This repository contains the implementation of Domain Driven Design and Clean Architecture in ASP.NET Core.

# ⚙️ Features
1.	Domain Driven Design
2.	REST API
3.	API Versioning
4.	Logging with Serilog
5.	EF Core Code First Approach 
6.	Microsoft SQL Server
7.	AutoMapper
8.	Swagger 
9.	LoggingMiddleware 
10.	ErrorHandlingMiddleware
11.	Fluent Assertions
12.	xUnit For UnitTest
13.	Moq For UnitTest
14.	Bogus For UnitTest
15.	Docker


# TODO
1.	Make Docker launch configurable seperate profile http and https
2.	Add another API
3.	Sql Post Gres
4.	Redis
5.	Azure hosting
6.	Store sensitive data in key vault
7.	Azure App Insight configuration
8.	Azure Service bus communication
9.	Azure containerization using Docker
10.	Kubernetes
11.	Angular
12.	SignalR
13.	Remove Auto Mapper
14.	CQRS without MediaR
